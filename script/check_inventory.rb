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
  wb_sold   = wb_nm_ids.empty? ? 0 :
    not_cancelled.(Ec::OrderItem.where(platform: "wb",   platform_sku_id: wb_nm_ids)).sum(:quantity)
  ozon_sold = ozon_skus.empty? ? 0 :
    not_cancelled.(Ec::OrderItem.where(platform: "ozon", platform_sku_id: ozon_skus)).sum(:quantity)
  sold = wb_sold + ozon_sold

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

  # WB 退货：从 raw_wb_stats_sales 出发，COUNT R 行（每行 = 1 件）
  wb_returns = wb_nm_ids.empty? ? 0 :
    RawWb::StatsSale
      .joins(<<~SQL)
        JOIN ec_orders
          ON ec_orders.external_order_number = raw_wb_stats_sales.g_number
         AND ec_orders.platform = 'wb'
        JOIN ec_order_items
          ON ec_order_items.order_id = ec_orders.id
         AND ec_order_items.platform_sku_id::bigint = raw_wb_stats_sales.nm_id
      SQL
      .where(ec_order_items: { platform_sku_id: wb_nm_ids })
      .where.not(ec_orders: { order_status: "cancelled" })
      .where("raw_wb_stats_sales.sale_id LIKE 'R%'")
      .count

  net_sales  = sold - ozon_returns - wb_returns
  book_stock = purchased - net_sales

  { purchased:, wb_sold:, ozon_sold:, sold:, ozon_returns:, wb_returns:, net_sales:, book_stock: }
end

# ─── 二、白俄可用库存（实时 API + DB 快照）──────────────────────────────────

# WB FBW 在库（实时 API）
# GET /api/v1/warehouse_remains（seller-analytics-api），3 步异步报告
def wb_fbw_from_api(sku_code)
  results = []
  RawWb::SellerAccount.where(is_active: true).each do |account|
    nm_ids = Ec::SkuProduct
      .joins(:store)
      .where(sku_code: sku_code, platform: "wb", ec_stores: { wb_raw_account_id: account.id })
      .pluck(:product_id)
    next if nm_ids.empty?

    begin
      client  = RawWb::WbClient.new(account.api_token)
      task_id = client.get(:seller_analytics, "/api/v1/warehouse_remains", groupByNm: true).dig("data", "taskId")
      loop do
        break if client.get(:seller_analytics, "/api/v1/warehouse_remains/tasks/#{task_id}/status").dig("data", "status") == "done"
        sleep 3
      end
      report = client.get(:seller_analytics, "/api/v1/warehouse_remains/tasks/#{task_id}/download")
      stock  = Array(report).select { |r| nm_ids.include?(r["nmId"].to_s) }.sum { |r| r["quantity"].to_i }
      results << { account: account.name, nm_ids:, stock: }
    rescue => e
      results << { account: account.name, nm_ids:, stock: 0, note: "API 错误: #{e.message.truncate(80)}" }
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

SKU_CODES.each do |sku_code|
  h1("SKU: #{sku_code}")

  h2("一、账面库存（DB，不调 API）")
  bs = calc_book_stock(sku_code)

  row "采购数量（received/closed）", bs[:purchased]
  row "销售数量",                    bs[:sold]
  row "  └ WB 销售",                bs[:wb_sold]
  row "  └ Ozon 销售",              bs[:ozon_sold]
  row "  − Ozon 退货",              bs[:ozon_returns], "SUM(raw_ozon_returns.quantity)"
  row "  − WB 退货",                bs[:wb_returns],   "COUNT(raw_wb_stats_sales R行)"
  row "净销售数量",                  bs[:net_sales]
  sep("·")
  row "账面库存 = 采购 − 净销售",    bs[:book_stock]

  h2("二、白俄可用库存（各平台在库）")

  total_wb_fbw   = 0
  total_wb_fbs   = 0
  total_ozon_fbo = 0
  total_ozon_fbs = 0

  h3("WB FBW 在库  实时 GET /api/v1/warehouse_remains（seller-analytics-api，异步报告）")
  wb_fbw_rows = wb_fbw_from_api(sku_code)
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
    wb_sold:         bs[:wb_sold],
    ozon_sold:       bs[:ozon_sold],
    sold:            bs[:sold],
    ozon_returns:    bs[:ozon_returns],
    wb_returns:      bs[:wb_returns],
    net_sales:       bs[:net_sales],
    book_stock:      bs[:book_stock],
    wb_fbw:          total_wb_fbw,
    wb_fbs:          total_wb_fbs,
    ozon_fbo:        total_ozon_fbo,
    ozon_fbs:        total_ozon_fbs,
    platform_total:  total_platform,
    blr_available:,
  }
end

# ─── CSV 汇总表 ──────────────────────────────────────────────────────────────

csv_path = Rails.root.join("tmp", "inventory_#{run_at.strftime('%Y%m%d_%H%M%S')}.csv")
CSV.open(csv_path, "w") do |csv|
  csv << %w[SKU 采购 WB销售 Ozon销售 总销售 Ozon退货 WB退货 净销售 账面库存 WB_FBW WB_FBS Ozon_FBO Ozon_FBS 平台在库 白俄可用]
  results.each do |r|
    csv << r.values_at(:sku_code, :purchased, :wb_sold, :ozon_sold, :sold,
                       :ozon_returns, :wb_returns, :net_sales, :book_stock,
                       :wb_fbw, :wb_fbs, :ozon_fbo, :ozon_fbs, :platform_total, :blr_available)
  end
end

puts "\n完成 #{Time.current.strftime('%H:%M:%S')}"
puts "结果已保存：#{csv_path}"
