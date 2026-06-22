#!/usr/bin/env ruby
# Sync WB order raw tables once.
#
# Usage:
#   bundle exec rails runner script/sync_wb_orders_once.rb
#   DAYS=90 bundle exec rails runner script/sync_wb_orders_once.rb
#   IMPORT_CHANGED_ONLY=1 bundle exec rails runner script/sync_wb_orders_once.rb
#
# Target tables:
#   raw_wb_orders        via sync_new_orders + sync_orders
#   raw_wb_stats_orders  via sync_stats_orders

$stdout.sync = true
Rails.logger = ActiveSupport::Logger.new($stdout)
Rails.logger.level = :info

DAYS = Integer(ENV.fetch("DAYS", "720"))
SYNC_KEYS = %i[
  sync_new_orders
  sync_orders
  sync_stats_orders
].freeze

started_at = Time.current

def format_elapsed(started_at)
  seconds = (Time.current - started_at).to_i
  format("%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
end

def print_step_result(step, result)
  if result[:error]
    puts "    #{step}: ERROR #{result[:error]}"
  elsif result.key?(:fetched)
    puts "    #{step}: fetched=#{result[:fetched]}, created=#{result[:created]}, updated=#{result[:updated]}, records=#{result[:ok]}"
  else
    puts "    #{step}: records=#{result[:ok]}"
  end
end

account_ids = Ec::Store
  .where(platform: "wb", is_active: true)
  .where.not(wb_raw_account_id: nil)
  .distinct
  .pluck(:wb_raw_account_id)

if account_ids.empty?
  raise "No active WB stores with linked raw accounts found"
end

accounts = RawWb::SellerAccount.where(id: account_ids).order(:id)

puts "[#{format_elapsed(started_at)}] Starting WB order sync once"
puts "  days=#{DAYS}"
puts "  accounts=#{accounts.size}"
puts "  steps=#{SYNC_KEYS.join(', ')}"

accounts.each do |account|
  account_started_at = Time.current
  puts "\n[#{format_elapsed(started_at)}] Account ##{account.id} #{account.name}"

  results = RawWb::DailySync
    .new(account, days: DAYS)
    .run(sync_keys: SYNC_KEYS)

  SYNC_KEYS.each do |step|
    print_step_result(step, results.fetch(step, { ok: 0 }))
  end

  elapsed = (Time.current - account_started_at).round(1)
  puts "  account_finished_in=#{elapsed}s"
end

if ENV["IMPORT_CHANGED_ONLY"] == "1"
  puts "\n[#{format_elapsed(started_at)}] Importing changed WB raw orders into Ec::Order"
  imported = Ec::OrderImport::Wb.new.call(synced_since: started_at)
else
  puts "\n[#{format_elapsed(started_at)}] Importing all WB raw orders into Ec::Order"
  imported = Ec::OrderImport::Wb.new.call
end
puts "[#{format_elapsed(started_at)}] Imported Ec::Order records=#{imported}"
puts "[#{format_elapsed(started_at)}] Done"
