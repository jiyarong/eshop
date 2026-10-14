require "optparse"
require "json"

options = {
  dry_run: true,
  spreadsheet_id: ENV.fetch("SKU_PROFIT_SPREADSHEET_ID", Ec::SkuProfitGoogleSheetImporter::DEFAULT_SPREADSHEET_ID),
  credentials_path: ENV["GOOGLE_SHEETS_CREDENTIALS_PATH"],
  json_path: ENV["SKU_PRICING_JSON_PATH"],
  effective_from: ENV.fetch("EFFECTIVE_FROM", Date.current.iso8601),
  version_name: ENV["VERSION_NAME"],
  report_path: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bin/rails runner script/import_sku_pricing_from_google_sheet.rb [options]"
  opts.on("--dry-run", "Read, assemble and calculate without writing (default)") { options[:dry_run] = true }
  opts.on("--apply", "Create draft versions") { options[:dry_run] = false }
  opts.on("--credentials PATH", "Google service-account JSON path") { |value| options[:credentials_path] = value }
  opts.on("--json PATH", "Read the three source tabs from a JSON dump instead of Google") { |value| options[:json_path] = value }
  opts.on("--spreadsheet-id ID", "Source Google spreadsheet ID") { |value| options[:spreadsheet_id] = value }
  opts.on("--effective-from DATE", "Version effective date") { |value| options[:effective_from] = value }
  opts.on("--version-name NAME", "Version name") { |value| options[:version_name] = value }
  opts.on("--report PATH", "Write the full JSON summary here") { |value| options[:report_path] = value }
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end

begin
  parser.parse!(ARGV)
  if options[:json_path].blank? && options[:credentials_path].blank?
    raise OptionParser::MissingArgument, "--json, SKU_PRICING_JSON_PATH, --credentials, or GOOGLE_SHEETS_CREDENTIALS_PATH"
  end

  effective_from = Date.iso8601(options.fetch(:effective_from))
rescue OptionParser::ParseError, Date::Error => error
  warn error.message
  warn parser
  exit 2
end

reader = if options[:json_path].present?
  Ec::SkuProfitPricingSheetImporter::JsonReader.new(path: options.fetch(:json_path))
else
  Ec::SkuProfitGoogleSheetImporter::GoogleSheetReader.new(
    credentials_path: options.fetch(:credentials_path),
    spreadsheet_id: options.fetch(:spreadsheet_id)
  )
end
summary = Ec::SkuProfitPricingSheetImporter.new(
  reader:,
  spreadsheet_id: options.fetch(:spreadsheet_id),
  effective_from:,
  version_name: options[:version_name],
  dry_run: options.fetch(:dry_run)
).call

json = JSON.pretty_generate(summary)
File.write(options.fetch(:report_path), json) if options[:report_path]
puts json
exit(summary.fetch(:ok) ? 0 : 1)
