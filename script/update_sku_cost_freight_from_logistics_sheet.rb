require "google/apis/sheets_v4"
require "googleauth"
require "json"
require "optparse"

DEFAULT_SPREADSHEET_ID = "1JbhVK4adukKD2b2KnAHHbruCsB9Y9G7xixFkVqMTrpg".freeze
DEFAULT_CREDENTIALS_PATH = Rails.root.join("config", "ecommerce-sheets-495606-2f1153f07139.json").to_s

options = {
  apply: ENV["APPLY"].to_s == "true",
  spreadsheet_id: ENV.fetch("LOGISTICS_SPREADSHEET_ID", DEFAULT_SPREADSHEET_ID),
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
  credentials_path = options[:credentials_path].presence || DEFAULT_CREDENTIALS_PATH
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

class SkuCodeNormalizer
  DASHES = /[\u058A\u05BE\u1400\u1806\u2010-\u2015\u2E17\u2E1A\u2E3A-\u2E3B\u2E40\u301C\u3030\u30A0\uFE31-\uFE32\uFE58\uFE63\uFF0D]/.freeze
  INVISIBLE = /[\u0000-\u001F\u007F\u00A0\u200B-\u200D\u2060\uFEFF]/.freeze

  def self.call(value)
    value.to_s
      .unicode_normalize(:nfkc)
      .gsub(DASHES, "-")
      .gsub(INVISIBLE, "")
      .upcase
      .gsub(/[^\p{Alnum}]/u, "")
  end
end

class SkuResolver
  Result = Data.define(:status, :skus, :raw_value, :details)

  def initialize(skus: Ec::Sku.all)
    @skus = skus.to_a
    @by_normalized_code = @skus.group_by { |sku| SkuCodeNormalizer.call(sku.sku_code) }
  end

  def resolve(candidate_cells)
    raw_value = candidate_cells.first.to_s
    normalized_candidates = candidate_cells.flat_map { |value| candidate_variants(value) }.uniq
    embedded_codes = embedded_code_keys(candidate_cells.first)
    collisions = (normalized_candidates + embedded_codes).uniq.filter_map do |candidate|
      matches = @by_normalized_code[candidate]
      [ candidate, matches.map(&:sku_code) ] if matches&.many?
    end
    return Result.new(status: :ambiguous, skus: [], raw_value:, details: collisions) if collisions.any?

    direct_matches = normalized_candidates.flat_map { |candidate| @by_normalized_code.fetch(candidate, []) }
    direct_matches.concat(embedded_codes.flat_map { |code| @by_normalized_code.fetch(code, []) })
    matches = direct_matches.uniq(&:id)

    if matches.empty?
      Result.new(status: :unmatched, skus: [], raw_value:, details: nil)
    else
      Result.new(status: :matched, skus: matches, raw_value:, details: nil)
    end
  end

  private

  def candidate_variants(value)
    text = value.to_s
    return [] if text.blank?

    variants = [ text, *text.lines ]
    variants += text.split(/[,;|]/)
    variants.map do |candidate|
      stripped = candidate.gsub(/\b(?:FBO|FBS|FBW)\b/i, "")
      SkuCodeNormalizer.call(stripped)
    end.reject(&:blank?)
  end

  def embedded_code_keys(value)
    normalized = SkuCodeNormalizer.call(value)
    return [] if normalized.blank?

    matching_codes = @by_normalized_code.keys.select { |code| code.length >= 4 && normalized.include?(code) }
    return [] if matching_codes.empty?

    max_length = matching_codes.map(&:length).max
    matching_codes.select { |code| code.length == max_length }
  end
end

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
resolver = SkuResolver.new

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

  resolution = resolver.resolve([ raw_sku ])
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
