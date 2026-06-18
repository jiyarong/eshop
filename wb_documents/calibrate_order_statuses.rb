# 全量校准 raw_wb_orders 的 supplierStatus / wbStatus
# POST /api/v3/orders/status，批量查询各账号订单最新状态
# 批量上限: 1000条/请求，rate limit: 20req/period（1s sleep 足够）
#
# 用法: bin/rails runner /tmp/calibrate_order_statuses.rb

BATCH_SIZE = 1000

def fetch_statuses(token, order_ids)
  results = []
  order_ids.each_slice(BATCH_SIZE) do |chunk|
    resp = RawWb::WbClient.new(token).post(:marketplace, '/api/v3/orders/status', { orders: chunk })
    results.concat(resp['orders'] || [])
    sleep 1
  end
  results
end

# Pure SQL UPDATE using a VALUES subquery — never inserts, never touches other columns.
def bulk_update_statuses(api_orders)
  return if api_orders.empty?

  # Build: UPDATE raw_wb_orders SET ... FROM (VALUES (...)) AS v WHERE wb_order_id = v.id
  values_sql = api_orders.map do |o|
    sup = ActiveRecord::Base.connection.quote(o['supplierStatus'])
    wb  = ActiveRecord::Base.connection.quote(o['wbStatus'])
    "(#{o['id'].to_i}, #{sup}, #{wb})"
  end.join(', ')

  sql = <<~SQL
    UPDATE raw_wb_orders AS o
    SET supplier_status = v.supplier_status,
        wb_status       = v.wb_status,
        updated_at      = NOW()
    FROM (VALUES #{values_sql}) AS v(wb_order_id, supplier_status, wb_status)
    WHERE o.wb_order_id = v.wb_order_id
  SQL

  ActiveRecord::Base.connection.execute(sql)
end

RawWb::SellerAccount.order(:id).each do |acc|
  ids = RawWb::Order.where(account_id: acc.id).pluck(:wb_order_id)
  puts "\n账号##{acc.id} (#{acc.name}): #{ids.size} 条"
  next if ids.empty?

  api_orders = fetch_statuses(acc.api_token, ids)
  puts "API 返回: #{api_orders.size} 条"
  next if api_orders.empty?

  # 分批 UPDATE（每批500条，避免 VALUES 子句过大）
  api_orders.each_slice(500) { |batch| bulk_update_statuses(batch) }

  wb_dist  = api_orders.group_by { |o| o['wbStatus'] }.transform_values(&:count)
  sup_dist = api_orders.group_by { |o| o['supplierStatus'] }.transform_values(&:count)
  puts "wbStatus 分布: #{wb_dist}"
  puts "supplierStatus 分布: #{sup_dist}"
end

puts "\n校准完成"
