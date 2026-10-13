# Recomputes the business statuses of every fulfillment.
#
#   bin/rails runner script/backfill_fulfillment_business_status.rb --dry-run
#   bin/rails runner script/backfill_fulfillment_business_status.rb
#   bin/rails runner script/backfill_fulfillment_business_status.rb --platform=wb
#
# --dry-run only reports how many fulfillments differ from the stored values (a consistency check).
dry_run = ARGV.include?("--dry-run")
platform = ARGV.filter_map { |argument| argument.delete_prefix("--platform=") if argument.start_with?("--platform=") }.first

result = Ec::FulfillmentBusinessStatus::Backfill.run(dry_run: dry_run, platform: platform)
puts "checked=#{result[:checked]} changed=#{result[:changed]} dry_run=#{dry_run}"
result[:samples].each do |sample|
  puts "  fulfillment #{sample[:fulfillment_id]}: #{sample[:from].join(' / ')} -> #{sample[:to].join(' / ')}"
end
