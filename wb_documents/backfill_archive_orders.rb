# 线上全量补录 WB FBS 归档订单（自包含，无需部署新代码）
# GET /api/marketplace/v3/fbs/orders/archive
# 按年月分页，upsert 更新最终状态，不覆盖 g_number
#
# 用法: bin/rails runner /tmp/backfill_archive_orders.rb

require 'net/http'
require 'json'

FROM_MONTH = Date.new(2024, 1, 1)

def fetch_archive_month(client, account_id, year, month, synced_at)
  cursor    = 0
  total_rows = []

  loop do
    resp = client.get(:marketplace, '/api/marketplace/v3/fbs/orders/archive',
                      year: year, month: month, next: cursor, limit: 1000)
    orders = resp['orders'] || []
    break if orders.empty?

    rows = orders.map do |o|
      product    = o['product']   || {}
      status     = o['status']    || {}
      price_info = o['priceInfo'] || {}
      {
        account_id:      account_id,
        wb_order_id:     o['id'],
        order_uid:       o['orderUid'],
        srid:            o['rid'],
        delivery_type:   'fbs',
        nm_id:           product['nmId'],
        chrt_id:         product['chrtId'],
        article:         product['article'],
        barcode:         Array(product['skus']).first,
        supplier_status: status['supplierStatus'] || 'new',
        wb_status:       status['wbStatus']       || 'waiting',
        price:           price_info['price'].to_f           / 100,
        converted_price: price_info['convertedPrice'].to_f  / 100,
        currency_code:   price_info['currencyCode'] || 643,
        warehouse_id:    nil,
        g_number:        nil,
        wb_office:       nil,
        required_meta:   o['metaDetails'] || [],
        optional_meta:   [],
        buyer_info:      nil,
        is_zero_order:   o['isZeroOrder'] || false,
        created_at:      o['createdAt'],
        updated_at:      Time.current,
        synced_at:       synced_at,
      }
    end

    RawWb::Order.upsert_all(rows,
                            unique_by:        :wb_order_id,
                            update_only:      %i[supplier_status wb_status required_meta is_zero_order updated_at synced_at],
                            record_timestamps: false)
    total_rows.concat(rows)

    cursor = resp['next'].to_i
    break if cursor.zero?
    sleep 1
  end

  total_rows
end

stores = Ec::Store.where(platform: 'wb', is_active: true)
abort "No active WB stores" if stores.none?

stores.each do |store|
  account = store.raw_wb_account
  unless account
    puts "[SKIP] store ##{store.id} #{store.store_name} — no linked WB account"
    next
  end

  puts "\n========================================="
  puts "Store: #{store.store_name} (account ##{account.id})"
  puts "========================================="

  client     = RawWb::WbClient.new(account.api_token)
  synced_at  = Time.current
  grand_total = 0
  current    = FROM_MONTH

  while current <= Date.current.beginning_of_month
    rows = fetch_archive_month(client, account.id, current.year, current.month, synced_at)
    if rows.any?
      puts "  #{current.strftime('%Y-%m')}: #{rows.size} 条"
      grand_total += rows.size
    end
    current = current >> 1
    sleep 1
  end

  puts "小计: #{grand_total} 条"
end

puts "\n全量补录完成"