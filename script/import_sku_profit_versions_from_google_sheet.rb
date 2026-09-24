require "optparse"
require "json"

options = {
  dry_run: true,
  spreadsheet_id: ENV.fetch("SKU_PROFIT_SPREADSHEET_ID", Ec::SkuProfitGoogleSheetImporter::DEFAULT_SPREADSHEET_ID),
  credentials_path: ENV["GOOGLE_SHEETS_CREDENTIALS_PATH"],
  xlsx_path: ENV["SKU_PROFIT_XLSX_PATH"],
  effective_from: ENV.fetch("EFFECTIVE_FROM", Date.current.iso8601),
  version_name: ENV["VERSION_NAME"]
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bin/rails runner script/import_sku_profit_versions_from_google_sheet.rb [options]"
  opts.on("--dry-run", "Read and validate without writing (default)") { options[:dry_run] = true }
  opts.on("--apply", "Create draft versions or backfill missing standard contexts") { options[:dry_run] = false }
  opts.on("--credentials PATH", "Google service-account JSON path") { |value| options[:credentials_path] = value }
  opts.on("--xlsx PATH", "Read the three source tabs from a local XLSX export") { |value| options[:xlsx_path] = value }
  opts.on("--spreadsheet-id ID", "Source Google spreadsheet ID") { |value| options[:spreadsheet_id] = value }
  opts.on("--effective-from DATE", "Initial version effective date") { |value| options[:effective_from] = value }
  opts.on("--version-name NAME", "Initial version name") { |value| options[:version_name] = value }
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end

begin
  parser.parse!(ARGV)
  if options[:xlsx_path].blank? && options[:credentials_path].blank?
    raise OptionParser::MissingArgument, "--xlsx, SKU_PROFIT_XLSX_PATH, --credentials, or GOOGLE_SHEETS_CREDENTIALS_PATH"
  end

  effective_from = Date.iso8601(options.fetch(:effective_from))
rescue OptionParser::ParseError, Date::Error => error
  warn error.message
  warn parser
  exit 2
end

reader = if options[:xlsx_path].present?
  Ec::SkuProfitGoogleSheetImporter::XlsxReader.new(path: options.fetch(:xlsx_path))
else
  Ec::SkuProfitGoogleSheetImporter::GoogleSheetReader.new(
    credentials_path: options.fetch(:credentials_path),
    spreadsheet_id: options.fetch(:spreadsheet_id)
  )
end
summary = Ec::SkuProfitGoogleSheetImporter.new(
  reader:,
  spreadsheet_id: options.fetch(:spreadsheet_id),
  effective_from:,
  version_name: options[:version_name],
  dry_run: options.fetch(:dry_run)
).call

puts JSON.pretty_generate(summary)
exit(summary.fetch(:ok) ? 0 : 1)
