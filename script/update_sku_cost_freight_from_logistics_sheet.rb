require "google/apis/sheets_v4"
require "googleauth"
require "json"
require "optparse"

require_dependency Rails.root.join("app/services/ec/sku_profit_google_sheet_importer.rb").to_s
require_dependency Rails.root.join("app/services/google_sheets/base_service.rb").to_s

options = {
  apply: ENV["APPLY"].to_s == "true",
  spreadsheet_id: ENV.fetch("LOGISTICS_SPREADSHEET_ID", Ec::SkuProfitGoogleSheetImporter::DEFAULT_SPREADSHEET_ID),
  sheet_id: Integer(ENV.fetch("LOGISTICS_SHEET_ID", "628756970")),
  credentials_path: ENV["GOOGLE_SHEETS_CREDENTIALS_PATH"],
  effective_on: ENV.fetch("EFFECTIVE_ON", "2026-09-01"),
  range_end: ENV.fetch("LOGISTICS_RANGE_END", "BA1039")
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bin/rails runner script/update_sku_cost_freight_from_logistics_sheet.rb [options]"
  opts.on("--dry-run", "Preview changes without writing (default)") { options[:apply] = false }
  opts.on("--apply", "Create/update Ec::SkuCost rows") { options[:apply] = true }
  opts.on("--credentials PATH", "Google service-account JSON path") { |value| options[:credentials_path] = value }
  opts.on("--spreadsheet-id ID", "Source Google spreadsheet ID") { |value| options[:spreadsheet_id] = value }
  opts.on("--sheet-id ID", Integer, "Source sheet gid") { |value| options[:sheet_id] = value }
  opts.on("--effective-on DATE", "Target Ec::SkuCost effective_on date") { |value| options[:effective_on] = value }
  opts.on("--range-end A1", "Bottom-right source range cell, default BA1039") { |value| options[:range_end] = value }
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end

begin
  parser.parse!(ARGV)
  target_date = Date.iso8601(options.fetch(:effective_on))
  credentials_path = options[:credentials_path].presence ||
    (defined?(GoogleSheets::BaseService::CREDENTIALS_PATH) && GoogleSheets::BaseService::CREDENTIALS_PATH.to_s)
  raise OptionParser::MissingArgument, "--credentials or GOOGLE_SHEETS_CREDENTIALS_PATH" if credentials_path.blank?
  raise OptionParser::InvalidArgument, "Google Sheets credential file does not exist: #{credentials_path}" unless File.file?(credentials_path)
rescue OptionParser::ParseError, Date::Error => error
  warn error.message
  warn parser
  exit 2
end

SKU_COLUMN_INDEX = 1
FREIGHT_COLUMN_INDEX = 34
FIRST_DATA_ROW_INDEX = 1

def column_name(index)
  value = index + 1
  name = +""
  while value.positive?
    value, remainder = (value - 1).divmod(26)
    name.prepend((65 + remainder).chr)
  end
  name
end

def decimal_value(value)
  text = value.to_s.strip
  return nil if text.blank?

  BigDecimal(text.tr("￥¥,", ""))
rescue ArgumentError
  nil
end

def fill_merged_cells(values, merges)
  filled = values.map(&:dup)
  merges.each do |merge|
    start_row = merge.start_row_index || 0
    end_row = merge.end_row_index || start_row + 1
    start_col = merge.start_column_index || 0
    end_col = merge.end_column_index || start_col + 1
    value = values.dig(start_row, start_col)
    next if value.to_s.blank?

    (start_row...end_row).each do |row_index|
      filled[row_index] ||= []
      (start_col...end_col).each { |col_index| filled[row_index][col_index] = value }
    end
  end
  filled
end

service = Google::Apis::SheetsV4::SheetsService.new
service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open(credentials_path),
  scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY
)

spreadsheet = service.get_spreadsheet(
  options.fetch(:spreadsheet_id),
  fields: "sheets(properties(sheetId,title),merges)"
)
sheet = spreadsheet.sheets.find { |candidate| candidate.properties.sheet_id == options.fetch(:sheet_id) }
raise "Google Sheet gid not found: #{options.fetch(:sheet_id)}" unless sheet

sheet_title = sheet.properties.title
range = "'#{sheet_title.gsub("'", "''")}'!A1:#{options.fetch(:range_end)}"
values = service.get_spreadsheet_values(
  options.fetch(:spreadsheet_id),
  range,
  value_render_option: "FORMATTED_VALUE"
).values || []
filled_values = fill_merged_cells(values, sheet.merges || [])
resolver = Ec::SkuProfitGoogleSheetImporter::SkuResolver.new

summary = {
  mode: options[:apply] ? "apply" : "dry_run",
  spreadsheet_id: options.fetch(:spreadsheet_id),
  sheet_id: options.fetch(:sheet_id),
  sheet_title:,
  effective_on: target_date.iso8601,
  source_rows: 0,
  latest_freights: 0,
  created: [],
  updated: [],
  unchanged: [],
  unmatched_rows: [],
  ambiguous_rows: [],
  invalid_freight_rows: [],
  missing_source_costs: [],
  future_only_costs: [],
  failures: []
}

latest_by_sku_code = {}
(FIRST_DATA_ROW_INDEX...filled_values.length).each do |row_index|
  raw_sku = filled_values.dig(row_index, SKU_COLUMN_INDEX).to_s.strip
  raw_freight = filled_values.dig(row_index, FREIGHT_COLUMN_INDEX).to_s.strip
  next if raw_sku.blank? && raw_freight.blank?

  summary[:source_rows] += 1
  next if raw_sku.blank? || raw_freight.blank?

  freight = decimal_value(raw_freight)
  if freight.nil?
    summary[:invalid_freight_rows] << { row: row_index + 1, sku: raw_sku, freight: raw_freight }
    next
  end

  resolution = resolver.resolve([ raw_sku ], platform: "wb")
  case resolution.status
  when :matched
    resolution.skus.each do |sku|
      latest_by_sku_code[sku.sku_code] = {
        row: row_index + 1,
        source_sku: raw_sku,
        sku_code: sku.sku_code,
        freight_to_by_cny: freight.to_s("F")
      }
    end
  when :unmatched
    summary[:unmatched_rows] << { row: row_index + 1, sku: raw_sku, freight: raw_freight }
  when :ambiguous
    summary[:ambiguous_rows] << { row: row_index + 1, sku: raw_sku, freight: raw_freight, details: resolution.details }
  end
end
summary[:latest_freights] = latest_by_sku_code.size

ActiveRecord::Base.transaction do
  latest_by_sku_code.values.sort_by { |item| item.fetch(:sku_code) }.each do |item|
    sku_code = item.fetch(:sku_code)
    freight = BigDecimal(item.fetch(:freight_to_by_cny))

    target_cost = Ec::SkuCost.find_by(sku_code:, effective_on: target_date)
    if target_cost
      previous = target_cost.freight_to_by_cny
      target_cost.freight_to_by_cny = freight
      record = item.merge(previous_freight_to_by_cny: previous&.to_s("F"))
      if target_cost.changed?
        target_cost.save! if options[:apply]
        summary[:updated] << record.merge(action: "update")
      else
        summary[:unchanged] << record.merge(action: "unchanged")
      end
      next
    end

    source_cost = Ec::SkuCost
      .where(sku_code:)
      .where("effective_on < ?", target_date)
      .order(effective_on: :desc, id: :desc)
      .first

    unless source_cost
      has_future_cost = Ec::SkuCost.where(sku_code:).where("effective_on > ?", target_date).exists?
      bucket = has_future_cost ? :future_only_costs : :missing_source_costs
      summary[bucket] << item
      next
    end

    copied_attributes = source_cost.attributes.except("id", "created_at", "updated_at")
    copied_attributes["effective_on"] = target_date
    copied_attributes["freight_to_by_cny"] = freight
    new_cost = Ec::SkuCost.new(copied_attributes)
    new_cost.save! if options[:apply]
    summary[:created] << item.merge(
      action: "create",
      source_cost_id: source_cost.id,
      source_effective_on: source_cost.effective_on.iso8601,
      previous_freight_to_by_cny: source_cost.freight_to_by_cny&.to_s("F")
    )
  rescue StandardError => error
    summary[:failures] << item.merge(error: "#{error.class}: #{error.message}")
  end

  raise ActiveRecord::Rollback unless options[:apply]
end

summary[:ok] = summary.values_at(:ambiguous_rows, :invalid_freight_rows, :failures).all?(&:empty?)
puts JSON.pretty_generate(summary)
exit(summary[:ok] ? 0 : 1)
