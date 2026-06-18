#!/usr/bin/env ruby
# 库存计算调试脚本
# 逻辑来源：docs/库存计算260615.md
#
# 用法：
#   bundle exec rails runner script/check_inventory.rb SKU1 SKU2 ...
#   bundle exec rails runner script/check_inventory.rb KJ-228-BK CYQ97-WT
#
# 输出分两大节：
#   一、账面库存：采购 − 净销售（含退货扣除），纯 DB 计算
#   二、白俄可用库存：账面库存 − 各平台在库
#
# WB FBW 在库：读 raw_wb_stocks 快照（warehouse_remains 需单独申请 Analytics token）
# WB FBS 在库：实时 POST /api/v3/stocks/{warehouseId}，参数 chrtIds
# Ozon FBO/FBS：实时 POST /v4/product/info/stocks，cursor 翻页

$stdout.sync = true
Rails.logger = Logger.new(IO::NULL)

SKU_CODES = ARGV.map(&:upcase).uniq

if SKU_CODES.empty?
  puts "用法: bundle exec rails runner script/check_inventory.rb SKU1 SKU2 ..."
  exit 1
end

# ─── 工具方法 ────────────────────────────────────────────────────────────────

def sep(char = "─", width = 70) = puts char * width
def h1(title)  = (sep("═"); puts "  #{title}"; sep("═"))
def h2(title)  = (sep; puts "  #{title}"; sep)
def h3(title)  = puts "\n▶ #{title}"
def row(label, value, note = nil)
  note_str = note ? "  ← #{note}" : ""
  puts "    %-30s %s%s" % [label, value, note_str]
end

# ─── 一、账面库存（纯 DB，不调 API）────────────────────────────────────────

def calc_book_stock(sku_code)
  purchased = Ec::SkuBatch
    .where(sku_code: sku_code, status: %w[received closed])
    .sum(:received_quantity)

  # 通过 ec_sku_products 取各平台原生商品 ID，不依赖 ec_order_items.sku_code
  # （sku_code 在订单导入时回填，若当时 ec_sku_products 无该映射则为 NULL）
  wb_nm_ids = Ec::SkuProduct
    .where(sku_code: sku_code, platform: "wb")
    .pluck(:product_id)

  # Ozon: ec_sku_products.product_id = ozon_product_id
  #       ec_order_items.platform_sku_id = ozon_sku，需通过 raw_ozon_products 转换
  ozon_product_ids = Ec::SkuProduct.where(sku_code: sku_code, platform: "ozon").pluck(:product_id)
  ozon_skus = ozon_product_ids.empty? ? [] :
    RawOzon::Product.where(ozon_product_id: ozon_product_ids)
                    .pluck(Arel.sql("raw_json->>'sku'")).compact

  not_cancelled = ->(rel) { rel.joins(:order).where.not(ec_orders: { order_status: "cancelled" }) }
  ozon_sold = ozon_skus.empty? ? 0 :
    not_cancelled.(Ec::OrderItem.where(platform: "ozon", platform_sku_id: ozon_skus)).sum(:quantity)

  # Ozon 退货：从 raw_ozon_returns 出发，SUM 退货表的 quantity
  ozon_returns = ozon_skus.empty? ? 0 :
    RawOzon::Return
      .joins(<<~SQL)
        JOIN ec_orders
          ON ec_orders.external_order_number = raw_ozon_returns.order_number
         AND ec_orders.platform = 'ozon'
        JOIN ec_order_items
          ON ec_order_items.order_id = ec_orders.id
         AND ec_order_items.platform_sku_id::bigint = raw_ozon_returns.ozon_sku
      SQL
      .where(ec_order_items: { platform_sku_id: ozon_skus })
      .where.not(ec_orders: { order_status: "cancelled" })
      .sum("raw_ozon_returns.quantity")

  # WB: 全量 FBS 订单（ec_order_items JOIN ec_order_fulfillments，fulfillment_type='fbs'）
  wb_fbs = wb_nm_ids.empty? ? 0 :
    not_cancelled.(
      Ec::OrderItem
        .joins(:fulfillment)
        .where(platform: "wb", platform_sku_id: wb_nm_ids)
        .where(ec_order_fulfillments: { fulfillment_type: "fbs" })
    ).sum(:quantity)

  # WB: FBW 送仓总量（supply_items JOIN supplies，用 wb_supply_id + account_id 关联）
  wb_supply = wb_nm_ids.empty? ? 0 :
    RawWb::SupplyItem
      .joins("INNER JOIN raw_wb_supplies ON raw_wb_supplies.wb_supply_id = raw_wb_supply_items.wb_supply_id AND raw_wb_supplies.account_id = raw_wb_supply_items.account_id")
      .where(nm_id: wb_nm_ids)
      .sum(:accepted_qty)

  # WB: 退货（只计 completed_dt 有值的，货真正到手才算有效退货）
  # FBS 退货：有 order_id，JOIN ec_order_fulfillments 过滤取消单
  # FBW 退货：order_id 为空（WB 不暴露 FBW 订单），直接按 nm_id 计数
  wb_gr_fbs = wb_nm_ids.empty? ? 0 :
    RawWb::GoodsReturn
      .joins(<<~SQL)
        JOIN ec_order_fulfillments
          ON ec_order_fulfillments.platform = 'wb'
         AND ec_order_fulfillments.external_fulfillment_id = raw_wb_goods_returns.order_id::text
        JOIN ec_orders
          ON ec_orders.id = ec_order_fulfillments.order_id
      SQL
      .where(raw_wb_goods_returns: { nm_id: wb_nm_ids })
      .where.not(raw_wb_goods_returns: { completed_dt: nil })
      .where.not(ec_orders: { order_status: "cancelled" })
      .count
  wb_gr_fbw = wb_nm_ids.empty? ? 0 :
    RawWb::GoodsReturn.where(nm_id: wb_nm_ids, order_id: nil).where.not(completed_dt: nil).count
  wb_goods_return = wb_gr_fbs + wb_gr_fbw

  wb_net     = wb_fbs + wb_supply - wb_goods_return
  net_sales  = wb_net + ozon_sold - ozon_returns
  book_stock = purchased - net_sales

  { purchased:, wb_fbs:, wb_supply:, wb_gr_fbs:, wb_gr_fbw:, wb_goods_return:, wb_net:,
    ozon_sold:, ozon_returns:, net_sales:, book_stock: }
end

# ─── 二、白俄可用库存（实时 API + DB 快照）──────────────────────────────────

# WB FBW 报告预拉取（每账号一次，供所有 SKU 共用）
# 返回 { account_id => { name:, report: [...] } }
def prefetch_wb_fbw_reports
  RawWb::SellerAccount.where(is_active: true).each_with_object({}) do |account, cache|
    begin
      client  = RawWb::WbClient.new(account.api_token)
      task_id = client.get(:seller_analytics, "/api/v1/warehouse_remains", groupByNm: true).dig("data", "taskId")
      loop do
        break if client.get(:seller_analytics, "/api/v1/warehouse_remains/tasks/#{task_id}/status").dig("data", "status") == "done"
        sleep 3
      end
      report = client.get(:seller_analytics, "/api/v1/warehouse_remains/tasks/#{task_id}/download")
      cache[account.id] = { name: account.name, report: Array(report) }
    rescue => e
      cache[account.id] = { name: account.name, report: [], error: e.message.truncate(80) }
    end
  end
end

# WB FBW 在库（从预拉取缓存查询，不再单独触发 API）
def wb_fbw_from_api(sku_code, fbw_cache)
  results = []
  RawWb::SellerAccount.where(is_active: true).each do |account|
    nm_ids = Ec::SkuProduct
      .joins(:store)
      .where(sku_code: sku_code, platform: "wb", ec_stores: { wb_raw_account_id: account.id })
      .pluck(:product_id)
    next if nm_ids.empty?

    cached = fbw_cache[account.id] || {}
    if cached[:error]
      results << { account: cached[:name] || account.name, nm_ids:, stock: 0, note: "API 错误: #{cached[:error]}" }
    else
      stock = cached[:report]
        .select { |r| nm_ids.include?(r["nmId"].to_s) }
        .sum { |r| Array(r["warehouses"]).find { |w| w["warehouseName"] == "Всего находится на складах" }&.dig("quantity").to_i }
      results << { account: cached[:name] || account.name, nm_ids:, stock: }
    end
  end
  results
end

# WB FBS 在库（实时 API）
def wb_fbs_from_api(sku_code)
  results = []
  RawWb::SellerAccount.where(is_active: true).each do |account|
    client = RawWb::WbClient.new(account.api_token)

    chrt_ids = Ec::SkuProduct
      .joins(:store)
      .where(sku_code: sku_code, platform: "wb", ec_stores: { wb_raw_account_id: account.id })
      .pluck(:platform_sku_id).compact

    if chrt_ids.empty?
      results << { account: account.name, stock: 0, note: "无 chrtId，跳过" }
      next
    end

    begin
      fbs_whs = Array(client.get(:marketplace, "/api/v3/warehouses")).select { |w| w["deliveryType"] == 1 }
      total = fbs_whs.sum do |wh|
        resp = client.post(:marketplace, "/api/v3/stocks/#{wh["id"]}", { chrtIds: chrt_ids.map(&:to_i) })
        (resp["stocks"] || []).sum { |s| s["amount"].to_i }
      end
      results << { account: account.name, chrt_ids:, warehouses: fbs_whs.size, stock: total }
    rescue => e
      results << { account: account.name, stock: 0, note: "API 错误: #{e.message.truncate(80)}" }
    end
  end
  results
end

# Ozon FBO + FBS 在库（实时 API）
def ozon_stocks_from_api(sku_code)
  results = []
  RawOzon::SellerAccount.where(is_active: true).each do |account|
    client = RawOzon::OzonClient.new(account.client_id, account.api_key)
    product_ids = Ec::SkuProduct
      .joins(:store)
      .where(sku_code: sku_code, platform: "ozon", ec_stores: { ozon_raw_account_id: account.id })
      .pluck(:product_id)

    fbo = 0
    fbs = 0
    matched = 0
    cursor = nil

    loop do
      body = { filter: {}, limit: 100 }
      body[:cursor] = cursor if cursor
      resp  = client.post("/v4/product/info/stocks", body)
      items = resp["items"] || []

      items.each do |item|
        next unless product_ids.include?(item["product_id"].to_s)
        matched += 1
        stocks = Array(item["stocks"])
        fbo += (stocks.find { |s| s["type"] == "fbo" } || {})["present"].to_i
        fbs += (stocks.find { |s| s["type"] == "fbs" } || {})["present"].to_i
      end

      cursor = resp["cursor"]
      break if cursor.blank? || items.size < 100
    end

    results << { account: account.company_name, fbo:, fbs:, matched: }
  rescue => e
    results << { account: account.company_name, fbo: 0, fbs: 0, matched: 0, note: "API 错误: #{e.message.truncate(80)}" }
  end
  results
end

# ─── 主循环：逐 SKU 输出 ────────────────────────────────────────────────────

require "csv"

run_at  = Time.current
results = []

puts "\n库存计算调试脚本  #{run_at.strftime('%Y-%m-%d %H:%M:%S')}"
puts "SKU 列表：#{SKU_CODES.join(', ')}"

puts "\n预拉取 WB FBW 库存报告（每账号一次）..."
fbw_cache = prefetch_wb_fbw_reports
puts "  完成，共 #{fbw_cache.size} 个账号"

SKU_CODES.each do |sku_code|
  h1("SKU: #{sku_code}")

  h2("一、账面库存（DB，不调 API）")
  bs = calc_book_stock(sku_code)

  row "采购数量（received/closed）", bs[:purchased]
  row "WB 部分（FBS − FBW送仓 + 退货）", bs[:wb_net]
  row "  └ FBS 全量订单",           bs[:wb_fbs],         "COUNT(raw_wb_orders delivery_type=fbs)"
  row "  └ FBW 送仓总量",           bs[:wb_supply],      "SUM(supply_items.accepted_qty)"
  row "  └ 退货（FBS）",             bs[:wb_gr_fbs],      "有 order_id，过滤取消单"
  row "  └ 退货（FBW）",             bs[:wb_gr_fbw],      "无 order_id，直接计数"
  row "Ozon 部分（销售 − 退货）",   bs[:ozon_sold].to_i - bs[:ozon_returns].to_i
  row "  └ Ozon 销售",              bs[:ozon_sold]
  row "  − Ozon 退货",              bs[:ozon_returns],   "SUM(raw_ozon_returns.quantity)"
  row "净销售数量",                  bs[:net_sales]
  sep("·")
  row "账面库存 = 采购 − 净销售",    bs[:book_stock]

  h2("二、白俄可用库存（各平台在库）")

  total_wb_fbw   = 0
  total_wb_fbs   = 0
  total_ozon_fbo = 0
  total_ozon_fbs = 0

  h3("WB FBW 在库  实时 GET /api/v1/warehouse_remains（seller-analytics-api，异步报告）")
  wb_fbw_rows = wb_fbw_from_api(sku_code, fbw_cache)
  if wb_fbw_rows.empty?
    puts "    （无 WB 账号或该 SKU 无 WB 商品）"
  else
    wb_fbw_rows.each do |r|
      puts "    #{r[:account]}  nm_id=#{r[:nm_ids].join(',')}  → #{r[:stock]} 件"
      total_wb_fbw += r[:stock].to_i
    end
    puts "    合计: #{total_wb_fbw} 件"
  end

  h3("WB FBS 在库  实时 POST /api/v3/stocks/{warehouseId}")
  wb_fbs_rows = wb_fbs_from_api(sku_code)
  if wb_fbs_rows.empty?
    puts "    （无 WB 账号）"
  else
    wb_fbs_rows.each do |r|
      if r[:note]
        puts "    #{r[:account]}  → #{r[:stock]} 件  [#{r[:note]}]"
      else
        puts "    #{r[:account]}  chrtIds=#{r[:chrt_ids].join(',')}  仓库数=#{r[:warehouses]}  → #{r[:stock]} 件"
      end
      total_wb_fbs += r[:stock].to_i
    end
    puts "    合计: #{total_wb_fbs} 件"
  end

  h3("Ozon FBO/FBS 在库  实时 POST /v4/product/info/stocks")
  ozon_rows = ozon_stocks_from_api(sku_code)
  if ozon_rows.empty?
    puts "    （无 Ozon 账号）"
  else
    ozon_rows.each do |r|
      note_str = r[:note] ? "  [#{r[:note]}]" : ""
      puts "    #{r[:account]}  命中 #{r[:matched]} 条#{note_str}"
      puts "      FBO=#{r[:fbo]}  FBS=#{r[:fbs]}"
      total_ozon_fbo += r[:fbo].to_i
      total_ozon_fbs += r[:fbs].to_i
    end
    puts "    FBO 合计: #{total_ozon_fbo} 件  FBS 合计: #{total_ozon_fbs} 件"
  end

  h2("汇总")
  total_platform = total_wb_fbw + total_wb_fbs + total_ozon_fbo + total_ozon_fbs
  blr_available  = bs[:book_stock] - total_platform

  row "账面库存",              bs[:book_stock]
  row "  − WB FBW（实时）",   total_wb_fbw
  row "  − WB FBS（实时）",   total_wb_fbs
  row "  − Ozon FBO（实时）", total_ozon_fbo
  row "  − Ozon FBS（实时）", total_ozon_fbs
  row "  = 平台在库合计",      total_platform
  sep("─")
  row "白俄可用库存",          blr_available

  results << {
    sku_code:,
    purchased:       bs[:purchased],
    wb_fbs:          bs[:wb_fbs],
    wb_supply:       bs[:wb_supply],
    wb_goods_return: bs[:wb_goods_return],
    wb_net:          bs[:wb_net],
    ozon_sold:       bs[:ozon_sold],
    ozon_returns:    bs[:ozon_returns],
    net_sales:       bs[:net_sales],
    book_stock:      bs[:book_stock],
    wb_fbw:          total_wb_fbw,
    wb_fbs_stock:    total_wb_fbs,
    ozon_fbo:        total_ozon_fbo,
    ozon_fbs:        total_ozon_fbs,
    platform_total:  total_platform,
    blr_available:,
  }
end

# ─── CSV 汇总表 ──────────────────────────────────────────────────────────────

csv_path = Rails.root.join("tmp", "inventory_#{run_at.strftime('%Y%m%d_%H%M%S')}.csv")
CSV.open(csv_path, "w") do |csv|
  csv << %w[SKU 采购 WB_FBS WB_FBW送仓 WB退货_FBS WB退货_FBW WB退货合计 WB净额 Ozon销售 Ozon退货 净销售 账面库存 WB_FBW在库 WB_FBS在库 Ozon_FBO Ozon_FBS 平台在库 白俄可用]
  results.each do |r|
    csv << r.values_at(:sku_code, :purchased, :wb_fbs, :wb_supply, :wb_gr_fbs, :wb_gr_fbw, :wb_goods_return, :wb_net,
                       :ozon_sold, :ozon_returns, :net_sales, :book_stock,
                       :wb_fbw, :wb_fbs_stock, :ozon_fbo, :ozon_fbs, :platform_total, :blr_available)
  end
end

puts "\n完成 #{Time.current.strftime('%H:%M:%S')}"
puts "结果已保存：#{csv_path}"
