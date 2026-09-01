require "optparse"

options = {}
OptionParser.new do |parser|
  parser.on("--sku-id ID", Integer) { |value| (options[:sku_ids] ||= []) << value }
  parser.on("--from DATE") { |value| options[:from_date] = Date.iso8601(value) }
  parser.on("--to DATE") { |value| options[:to_date] = Date.iso8601(value) }
  parser.on("--rebuild-stock") { options[:rebuild_stock] = true }
end.parse!(ARGV)

result = if options.delete(:rebuild_stock)
  Ec::SkuLifecycleEventProjector.rebuild_stock_history(**options)
else
  Ec::SkuLifecycleEventProjector.run(**options)
end

puts JSON.pretty_generate(result)
