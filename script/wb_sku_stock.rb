#!/usr/bin/env ruby
# Query WB stock for one store and one SKU directly from WB APIs.
#
# Usage:
#   bundle exec rails runner script/wb_sku_stock.rb TaxiLink KJ-228-BK
#   STORE=TaxiLink SKU=KJ-228-BK bundle exec rails runner script/wb_sku_stock.rb

$stdout.sync = true
Rails.logger = Logger.new(IO::NULL)

def print_raw(title, payload)
  puts "\n--- RAW #{title} ---"
  puts JSON.pretty_generate(payload)
end

store_key = ARGV[0].presence || ENV["STORE"].presence
sku_code = (ARGV[1].presence || ENV["SKU"].presence)&.upcase

if store_key.blank? || sku_code.blank?
  puts "Usage: bundle exec rails runner script/wb_sku_stock.rb STORE SKU"
  puts "   or: STORE=TaxiLink SKU=KJ-228-BK bundle exec rails runner script/wb_sku_stock.rb"
  exit 1
end

store = Ec::Store
  .where(platform: "wb")
  .where("id::text = :key OR store_name ILIKE :name", key: store_key.to_s, name: store_key.to_s)
  .first

unless store
  puts "WB store not found: #{store_key}"
  exit 1
end

account = store.raw_wb_account
unless account
  puts "WB raw account not linked for store ##{store.id} #{store.store_name}"
  exit 1
end

products = Ec::SkuProduct.where(store: store, sku_code: sku_code, platform: "wb").to_a
if products.empty?
  puts "No WB product binding found for store=#{store.store_name}, sku=#{sku_code}"
  exit 1
end

client = RawWb::WbClient.new(account.api_token)
nm_ids = products.map(&:product_id).compact_blank.uniq
chrt_ids = products.map(&:platform_sku_id).compact_blank.uniq

puts "Store: #{store.store_name} (store_id=#{store.id}, account_id=#{account.id})"
puts "SKU: #{sku_code}"
puts "WB nmIds: #{nm_ids.join(', ').presence || '-'}"
puts "WB chrtIds: #{chrt_ids.join(', ').presence || '-'}"

fbw_total = 0
fbw_rows = []
begin
  task_response = client.get(:seller_analytics, "/api/v1/warehouse_remains", groupByNm: true)
  print_raw("GET /api/v1/warehouse_remains", task_response)
  task_id = task_response.dig("data", "taskId")
  raise "warehouse_remains did not return taskId" if task_id.blank?

  loop do
    status_response = client.get(:seller_analytics, "/api/v1/warehouse_remains/tasks/#{task_id}/status")
    print_raw("GET /api/v1/warehouse_remains/tasks/#{task_id}/status", status_response)
    status = status_response.dig("data", "status")
    break if status == "done"
    sleep 3
  end

  download_response = client.get(:seller_analytics, "/api/v1/warehouse_remains/tasks/#{task_id}/download")
  print_raw("GET /api/v1/warehouse_remains/tasks/#{task_id}/download", download_response)
  report = Array(download_response)
  report.each do |row|
    next unless nm_ids.include?(row["nmId"].to_s)

    Array(row["warehouses"]).each do |warehouse|
      quantity = warehouse["quantity"].to_i
      next if quantity.zero?

      fbw_rows << [warehouse["warehouseName"], quantity]
      fbw_total += quantity if warehouse["warehouseName"] == "Всего находится на складах"
    end
  end
rescue => e
  puts "FBW API error: #{e.message}"
end

fbs_total = 0
fbs_rows = []
begin
  if chrt_ids.empty?
    puts "FBS skipped: no chrtIds in ec_sku_products.platform_sku_id"
  else
    warehouses_response = client.get(:marketplace, "/api/v3/warehouses")
    print_raw("GET /api/v3/warehouses", warehouses_response)
    warehouses = Array(warehouses_response).select { |warehouse| warehouse["deliveryType"] == 1 }
    warehouses.each do |warehouse|
      response = client.post(:marketplace, "/api/v3/stocks/#{warehouse["id"]}", { chrtIds: chrt_ids.map(&:to_i) })
      print_raw("POST /api/v3/stocks/#{warehouse["id"]}", response)
      quantity = Array(response["stocks"]).sum { |stock| stock["amount"].to_i }
      next if quantity.zero?

      fbs_rows << [warehouse["name"] || warehouse["officeName"] || warehouse["id"], quantity]
      fbs_total += quantity
    end
  end
rescue => e
  puts "FBS API error: #{e.message}"
end

puts "\nFBW stock: #{fbw_total}"
fbw_rows.each { |name, quantity| puts "  #{name}: #{quantity}" }

puts "\nFBS stock: #{fbs_total}"
fbs_rows.each { |name, quantity| puts "  #{name}: #{quantity}" }

puts "\nTotal stock: #{fbw_total + fbs_total}"
