#!/usr/bin/env ruby

require_relative "../config/environment"

rows = Ec::UnboundRawProductReport.call

puts "Unbound raw products: #{rows.size}"

if rows.empty?
  puts "No raw_ozon_products or raw_wb_products need ec_sku_products bindings."
  exit
end

headers = [
  "platform",
  "store",
  "account",
  "product_id",
  "offer_id",
  "platform_sku_id",
  "product_name",
  "synced_at"
]

values = rows.map do |row|
  [
    row.platform,
    "#{row.store_name} (##{row.store_id})",
    "#{row.account_name || '-'} (##{row.account_id})",
    row.product_id,
    row.offer_id,
    row.platform_sku_id,
    row.product_name,
    row.synced_at&.strftime("%Y-%m-%d %H:%M:%S")
  ].map { |value| value.to_s.presence || "-" }
end

widths = headers.each_index.map do |index|
  ([headers[index]] + values.map { |row| row[index] }).map(&:length).max
end

format = widths.map { |width| "%-#{width}s" }.join("  ")

puts format % headers
puts widths.map { |width| "-" * width }.join("  ")
values.each { |row| puts format % row }
