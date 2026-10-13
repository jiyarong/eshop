# Recomputes the business statuses of every fulfillment.
#
#   bin/rails runner script/backfill_fulfillment_business_status.rb --dry-run
#   bin/rails runner script/backfill_fulfillment_business_status.rb
#   bin/rails runner script/backfill_fulfillment_business_status.rb --platform=wb
#
# --dry-run only reports how many fulfillments differ from the stored values (a consistency check).
# Any other argument aborts, so a typo can never turn a dry run into a real write.
platforms = Ec::Order::PLATFORMS.values
usage = "usage: backfill_fulfillment_business_status.rb [--dry-run] [--platform=#{platforms.join('|')}]"
dry_run = false
platform = nil

ARGV.each do |argument|
  if argument == "--dry-run"
    dry_run = true
  elsif argument.start_with?("--platform=") && platforms.include?(argument.delete_prefix("--platform="))
    platform = argument.delete_prefix("--platform=")
  else
    abort "unknown argument #{argument.inspect}\n#{usage}"
  end
end

result = Ec::FulfillmentBusinessStatus::Backfill.run(dry_run: dry_run, platform: platform)
puts "checked=#{result[:checked]} changed=#{result[:changed]} dry_run=#{dry_run}"
result[:samples].each do |sample|
  puts "  fulfillment #{sample[:fulfillment_id]}: #{sample[:from].join(' / ')} -> #{sample[:to].join(' / ')}"
end
