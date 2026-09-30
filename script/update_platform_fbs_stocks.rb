# frozen_string_literal: true

# Usage:
#   PLAN_PATH=/rails/tmp/fbs_stock_plan.json bin/rails runner script/update_platform_fbs_stocks.rb
#   APPLY=1 PLAN_PATH=/rails/tmp/fbs_stock_plan.json bin/rails runner script/update_platform_fbs_stocks.rb
#
# Plan format:
# {
#   "updates": [
#     { "platform": "wb", "account_id": 2, "warehouse_id": 1712320,
#       "barcode": "2039679513137", "sku_code": "LDD002", "stock": 10 },
#     { "platform": "ozon", "account_id": 1, "warehouse_id": 1020005028961680,
#       "offer_id": "LDD002", "sku_code": "LDD002", "stock": 20 }
#   ]
# }

require "json"

plan_path = ENV["PLAN_PATH"].presence
raise ArgumentError, "PLAN_PATH is required" unless plan_path
raise ArgumentError, "plan file not found: #{plan_path}" unless File.file?(plan_path)

plan = JSON.parse(File.read(plan_path))
apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch("APPLY", false))

Ec::PlatformFbsStockUpdater.new(
  updates: plan.fetch("updates"),
  apply: apply
).call
