# 清理 WB stats 原始数据 + ec_orders 中非 FBS 的 WB 订单
# 运行: bundle exec rails runner script/cleanup_wb_stats_and_orders.rb

ActiveRecord::Base.transaction do
  # ── 1. 清空 raw_wb_stats_orders ────────────────────────────────────────────
  count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM raw_wb_stats_orders").first["count"].to_i
  puts "raw_wb_stats_orders: #{count} 条 → 删除中..."
  ActiveRecord::Base.connection.execute("TRUNCATE TABLE raw_wb_stats_orders")
  puts "raw_wb_stats_orders ✓ 已清空"

  # ── 2. 清空 raw_wb_stats_sales ─────────────────────────────────────────────
  count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM raw_wb_stats_sales").first["count"].to_i
  puts "raw_wb_stats_sales: #{count} 条 → 删除中..."
  ActiveRecord::Base.connection.execute("TRUNCATE TABLE raw_wb_stats_sales")
  puts "raw_wb_stats_sales ✓ 已清空"

  # ── 3. 找出 ec_orders 中平台为 wb 且 fulfillment 不是 fbs 的订单 ID ────────
  #
  # 逻辑：在 ec_order_fulfillments 里找 platform='wb' AND fulfillment_type!='fbs'
  # 取出对应的 order_id，再删除这些 ec_orders（依赖 dependent: :destroy 级联删除）
  #
  # 注意：ozon 订单完全不在此查询范围内

  non_fbs_order_ids = Ec::OrderFulfillment
    .where(platform: "wb")
    .where.not(fulfillment_type: "fbs")
    .distinct
    .pluck(:order_id)

  puts "\nec_orders (wb, non-fbs): 找到 #{non_fbs_order_ids.size} 条关联 order"

  if non_fbs_order_ids.empty?
    puts "无需删除，跳过。"
  else
    # 预览：打印 fulfillment_type 分布
    dist = Ec::OrderFulfillment
      .where(order_id: non_fbs_order_ids, platform: "wb")
      .group(:fulfillment_type)
      .count
    puts "fulfillment_type 分布: #{dist}"

    # 删除 ec_orders（级联删除 fulfillments / items / source_links）
    deleted = Ec::Order.where(id: non_fbs_order_ids, platform: "wb").destroy_all
    puts "ec_orders ✓ 已删除 #{deleted.size} 条（及其关联 fulfillments/items/source_links）"
  end

  # ── 4. 验证：确认 ozon 数据完好 ────────────────────────────────────────────
  ozon_count = Ec::Order.where(platform: "ozon").count
  wb_fbs_count = Ec::OrderFulfillment.where(platform: "wb", fulfillment_type: "fbs").count
  wb_non_fbs_count = Ec::OrderFulfillment.where(platform: "wb").where.not(fulfillment_type: "fbs").count

  puts "\n── 验证 ──────────────────────────────────────────────────────────"
  puts "ozon 订单（应不变）: #{ozon_count} 条"
  puts "wb fbs fulfillments（保留）: #{wb_fbs_count} 条"
  puts "wb non-fbs fulfillments（应为 0）: #{wb_non_fbs_count} 条"

  raise "wb non-fbs 仍有残留，回滚！" if wb_non_fbs_count > 0
  puts "\n全部完成，事务提交。"
end
