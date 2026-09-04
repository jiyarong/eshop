#!/usr/bin/env ruby
# Refresh Ozon product prices, including the customer (Ozon Bank card) price.
# The listing API uses raw_ozon_product_prices.customer_price as its final price.
#
# Preview the accounts that will be refreshed:
#   bin/rails runner script/backfill_ozon_product_prices.rb
# Apply by calling the Ozon prices API:
#   APPLY=1 bin/rails runner script/backfill_ozon_product_prices.rb

$stdout.sync = true
Rails.logger = ActiveSupport::Logger.new($stdout)
Rails.logger.level = :info

account_ids = Ec::Store
  .where(platform: "ozon", is_active: true)
  .where.not(ozon_raw_account_id: nil)
  .distinct
  .pluck(:ozon_raw_account_id)

raise "No active Ozon stores with linked raw accounts found" if account_ids.empty?

accounts = RawOzon::SellerAccount.where(id: account_ids).order(:id)
puts "Ozon accounts to refresh: #{accounts.count}"

accounts.each do |account|
  count = RawOzon::ProductPrice.where(account_id: account.id).count
  puts "  ##{account.id} #{account.company_name}: #{count} stored price rows"
end

unless ENV["APPLY"] == "1"
  puts "Preview only. Run with APPLY=1 to refresh prices from the Ozon API."
  exit 0
end

accounts.each do |account|
  puts "Refreshing account ##{account.id} #{account.company_name}"
  result = RawOzon::DailySync.new(account, days: 1).run(sync_keys: [:sync_product_prices])
  outcome = result.fetch(:sync_product_prices, {})
  if outcome[:error]
    puts "  ERROR: #{outcome[:error]}"
  else
    puts "  updated prices: #{outcome[:ok]}"
  end
end

puts "Done"
