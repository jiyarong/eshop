# Usage:
#   bin/rails runner script/backfill_ec_returns.rb
#   PLATFORM=ozon bin/rails runner script/backfill_ec_returns.rb

platform = ENV["PLATFORM"].presence
result = Ec::Returns::Backfill.run(platform: platform)
puts JSON.pretty_generate(result)
