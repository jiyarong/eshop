#!/usr/bin/env ruby
# Delete normalized WB orders and rebuild them from existing raw WB data.
#
# Usage:
#   CONFIRM=reset_wb_orders bundle exec rails runner script/reset_and_sync_wb_orders.rb
#   CONFIRM=reset_wb_orders SYNC_RAW=1 DAYS=720 bundle exec rails runner script/reset_and_sync_wb_orders.rb

$stdout.sync = true
Rails.logger = ActiveSupport::Logger.new($stdout)
Rails.logger.level = :info

CONFIRM_VALUE = "reset_wb_orders"
DAYS = Integer(ENV.fetch("DAYS", "720"))
SYNC_KEYS = %i[
  sync_new_orders
  sync_orders
  sync_stats_orders
].freeze

unless ENV["CONFIRM"] == CONFIRM_VALUE
  puts "Refusing to delete data."
  puts "Run with CONFIRM=#{CONFIRM_VALUE} bundle exec rails runner script/reset_and_sync_wb_orders.rb"
  exit 1
end

started_at = Time.current

def elapsed(started_at)
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

def active_wb_accounts
  account_ids = Ec::Store
    .where(platform: "wb", is_active: true)
    .where.not(wb_raw_account_id: nil)
    .distinct
    .pluck(:wb_raw_account_id)

  RawWb::SellerAccount.where(id: account_ids).order(:id)
end

def delete_ec_wb_orders
  order_scope = Ec::Order.where(platform: "wb")
  fulfillment_scope = Ec::OrderFulfillment.where(order_id: order_scope.select(:id))

  Ec::OrderSourceLink
    .where(order_id: order_scope.select(:id))
    .or(Ec::OrderSourceLink.where(fulfillment_id: fulfillment_scope.select(:id)))
    .delete_all
  Ec::OrderItem
    .where(order_id: order_scope.select(:id))
    .or(Ec::OrderItem.where(fulfillment_id: fulfillment_scope.select(:id)))
    .delete_all
  fulfillment_scope.delete_all
  deleted_orders = order_scope.delete_all

  puts "  deleted ec_orders=#{deleted_orders}"
end

puts "[#{elapsed(started_at)}] Resetting normalized WB order data"
ActiveRecord::Base.transaction do
  delete_ec_wb_orders
end

accounts = active_wb_accounts
raise "No active WB stores with linked raw accounts found" if accounts.empty?

if ENV["SYNC_RAW"] == "1"
  puts "\n[#{elapsed(started_at)}] Syncing WB order raw tables"
  puts "  days=#{DAYS}"
  puts "  accounts=#{accounts.size}"
  puts "  steps=#{SYNC_KEYS.join(', ')}"

  accounts.each do |account|
    account_started_at = Time.current
    puts "\n[#{elapsed(started_at)}] Account ##{account.id} #{account.name}"

    results = RawWb::DailySync
      .new(account, days: DAYS)
      .run(sync_keys: SYNC_KEYS)

    SYNC_KEYS.each do |step|
      print_step_result(step, results.fetch(step, { ok: 0 }))
    end

    puts "  account_finished_in=#{(Time.current - account_started_at).round(1)}s"
  end
else
  puts "\n[#{elapsed(started_at)}] Skipping raw WB sync. Set SYNC_RAW=1 to refresh raw_wb_orders/raw_wb_stats_orders."
end

puts "\n[#{elapsed(started_at)}] Rebuilding Ec::Order from WB raw data"
imported = Ec::OrderImport::Wb.new.call
puts "[#{elapsed(started_at)}] Imported Ec::Order records=#{imported}"
puts "[#{elapsed(started_at)}] Done"
