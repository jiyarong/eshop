#!/usr/bin/env ruby
# Refresh WB product prices so the API price units and currencyIsoCode4217 are stored correctly.
#
# Preview missing currency rows:
#   bin/rails runner script/backfill_wb_product_price_currencies.rb
# Apply by calling the WB prices API for every active WB account:
#   APPLY=1 bin/rails runner script/backfill_wb_product_price_currencies.rb

$stdout.sync = true
Rails.logger = ActiveSupport::Logger.new($stdout)
Rails.logger.level = :info

account_ids = Ec::Store
  .where(platform: "wb", is_active: true)
  .where.not(wb_raw_account_id: nil)
  .distinct
  .pluck(:wb_raw_account_id)

raise "No active WB stores with linked raw accounts found" if account_ids.empty?

accounts = RawWb::SellerAccount.where(id: account_ids).order(:id)
missing_count = RawWb::ProductPrice.where(account_id: account_ids, currency_code: [nil, ""]).count

puts "WB product prices missing currency: #{missing_count}"

unless ENV["APPLY"] == "1"
  puts "Preview only. Run with APPLY=1 to refresh prices from the WB API."
  exit 0
end

accounts.each do |account|
  puts "Refreshing account ##{account.id} #{account.name}"
  result = RawWb::DailySync.new(account, days: 1).run(sync_keys: [:sync_product_prices])
  outcome = result.fetch(:sync_product_prices, {})
  if outcome[:error]
    puts "  ERROR: #{outcome[:error]}"
  else
    puts "  updated prices: #{outcome[:ok]}"
  end
end

puts "Done"
