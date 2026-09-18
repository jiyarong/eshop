# frozen_string_literal: true

# Usage:
#   bundle exec rails runner script/import_sku_costs_from_logistics_xlsx.rb /path/to/workbook.xlsx
#   APPLY=1 bundle exec rails runner script/import_sku_costs_from_logistics_xlsx.rb /path/to/workbook.xlsx
#
# 从物流台账 Logistics 表读取 SKU（B 列）、国内采购价（J 列）、平摊每件运费（AI 列），
# 写入 Ec::SkuCost：
# - 同一 SKU 出现多行时，取表格中最靠下（最新）的一行；
# - 该 SKU 尚无成本记录，或最新一条记录未填完（算不出货物总成本）——直接原地更新该记录；
# - 最新一条记录已填完，且生效日期早于今天——复制出一个新版本，生效日期改为当天；
# - 最新一条记录的生效日期已经是今天——直接原地更新（同一天不能有两条记录）。
# 导入时清关杂费为空则按采购价的 10% 补齐，关税率、进口增值税为空则分别默认 0.1、0.2。
# 默认是 dry run，设置 APPLY=1 才会写入。

require "zip"
require "nokogiri"

class SkuCostsFromLogisticsXlsxImport
  DEFAULT_XLSX_PATH = Rails.root.join("tmp", "logistics_costs.xlsx")
  SHEET_NAME = "Logistics"
  HEADER_ROW = 1
  REQUIRED_HEADERS = {
    "B" => "产品",
    "J" => "国内采购价",
    "AI" => "平摊每件运费"
  }.freeze
  DEFAULT_CUSTOMS_MISC_RATE = BigDecimal("0.1")
  DEFAULT_CUSTOMS_DUTY_RATE = BigDecimal("0.1")
  DEFAULT_IMPORT_VAT_RATE = BigDecimal("0.2")

  Row = Data.define(:source_row, :sku_code, :purchase_price_cny, :freight_to_by_cny)
  Result = Struct.new(
    :created, :updated_in_place, :versioned, :unchanged, :missing_sku, :total,
    keyword_init: true
  )

  def initialize(xlsx_path: DEFAULT_XLSX_PATH, rows: nil, env: ENV, stdout: $stdout, today: Date.current)
    @xlsx_path = Pathname(xlsx_path)
    @rows = rows
    @dry_run = !ActiveModel::Type::Boolean.new.cast(env.fetch("APPLY", false))
    @stdout = stdout
    @today = today
  end

  def call
    source_rows = rows || parse_rows
    result = Result.new(created: 0, updated_in_place: 0, versioned: 0, unchanged: 0,
                        missing_sku: 0, total: source_rows.size)

    stdout.puts "SKU cost import from Logistics workbook (#{dry_run ? 'dry run' : 'apply'})"
    stdout.puts "Source: #{xlsx_path}" unless rows
    stdout.puts "SKUs to import: #{result.total}"

    ApplicationRecord.transaction do
      source_rows.each { |row| import_row(row, result) }
      raise ActiveRecord::Rollback if dry_run
    end

    stdout.puts "Created: #{result.created}"
    stdout.puts "Updated in place: #{result.updated_in_place}"
    stdout.puts "New version created: #{result.versioned}"
    stdout.puts "Unchanged: #{result.unchanged}"
    stdout.puts "Missing SKU: #{result.missing_sku}"
    stdout.puts "No data changed. Set APPLY=1 to write." if dry_run
    result
  end

  private

  attr_reader :xlsx_path, :rows, :dry_run, :stdout, :today

  def parse_rows
    raise ArgumentError, "XLSX file not found: #{xlsx_path}" unless xlsx_path.file?

    candidates = Zip::File.open(xlsx_path) do |archive|
      shared_strings = read_shared_strings(archive)
      sheet_path = sheet_path_for(archive, SHEET_NAME)
      document = xml(archive.read(sheet_path))
      validate_headers!(document, shared_strings)

      document.xpath("//sheetData/row[number(@r) > #{HEADER_ROW}]").filter_map do |row_node|
        values = row_values(row_node, shared_strings)
        sku_code = normalize_sku(values["B"])
        next if sku_code.blank?

        purchase_price = parse_decimal(values["J"], row_node["r"].to_i, "J")
        freight = parse_decimal(values["AI"], row_node["r"].to_i, "AI")
        next if purchase_price.nil? && freight.nil?

        Row.new(
          source_row: row_node["r"].to_i,
          sku_code: sku_code,
          purchase_price_cny: purchase_price,
          freight_to_by_cny: freight
        )
      end
    end

    # 同一 SKU 出现多行时，取表格中最靠下（最新）的一行
    candidates
      .group_by(&:sku_code)
      .map { |_sku_code, sku_rows| sku_rows.max_by(&:source_row) }
      .sort_by(&:source_row)
  rescue Zip::Error, Nokogiri::XML::SyntaxError => error
    raise ArgumentError, "Invalid XLSX file #{xlsx_path}: #{error.message}"
  end

  def xml(content)
    Nokogiri::XML(content) { |config| config.strict.nonet }.tap(&:remove_namespaces!)
  end

  def read_shared_strings(archive)
    entry = archive.find_entry("xl/sharedStrings.xml")
    return [] unless entry

    xml(entry.get_input_stream.read).xpath("//si").map do |item|
      item.xpath(".//t").map(&:text).join
    end
  end

  def sheet_path_for(archive, sheet_name)
    workbook = xml(archive.read("xl/workbook.xml"))
    sheet = workbook.xpath("//sheets/sheet").find { |node| node["name"] == sheet_name }
    raise ArgumentError, "Worksheet #{sheet_name} was not found in #{xlsx_path}" unless sheet

    relationships = xml(archive.read("xl/_rels/workbook.xml.rels"))
    relationship = relationships.xpath("//Relationship").find do |node|
      node["Id"] == sheet["id"] || node["Id"] == sheet["r:id"]
    end
    raise ArgumentError, "Worksheet relationship for #{sheet_name} was not found" unless relationship

    "xl/#{relationship['Target'].sub(%r{\A/}, '').sub(%r{\Axl/}, '')}"
  end

  def validate_headers!(document, shared_strings)
    header_row = document.at_xpath("//sheetData/row[@r='#{HEADER_ROW}']")
    raise ArgumentError, "Header row #{HEADER_ROW} was not found" unless header_row

    headers = row_values(header_row, shared_strings)
    invalid = REQUIRED_HEADERS.filter_map do |column, expected|
      actual = headers[column].to_s.gsub(/\s+/, " ").strip
      column unless actual.start_with?(expected)
    end
    return if invalid.empty?

    raise ArgumentError, "Unexpected headers in columns: #{invalid.join(', ')}"
  end

  def row_values(row_node, shared_strings)
    row_node.xpath("./c").each_with_object({}) do |cell, values|
      column = cell["r"].to_s[/[A-Z]+/]
      next unless REQUIRED_HEADERS.key?(column)

      raw_value = cell.at_xpath("./v")&.text
      values[column] = case cell["t"]
      when "s" then raw_value && shared_strings.fetch(raw_value.to_i)
      when "inlineStr" then cell.xpath(".//t").map(&:text).join
      else raw_value
      end
    end
  end

  def normalize_sku(value)
    value.to_s.split(/\s+/).first.to_s.strip.upcase
  end

  def parse_decimal(value, source_row, column)
    return nil if value.blank?

    cleaned = value.to_s.gsub(/[￥¥,\s]/, "")
    return nil if cleaned.blank?

    BigDecimal(cleaned)
  rescue ArgumentError
    raise ArgumentError, "Invalid decimal value at Logistics!#{column}#{source_row}: #{value.inspect}"
  end

  def import_row(row, result)
    sku = Ec::Sku.find_by(sku_code: row.sku_code)
    unless sku
      stdout.puts "SKIP row #{row.source_row}: SKU not found: #{row.sku_code}"
      result.missing_sku += 1
      return
    end

    existing = Ec::SkuCost.where(sku_code: sku.sku_code).order(effective_on: :desc, id: :desc).first
    cost, action = target_cost_record(sku.sku_code, existing)

    cost.purchase_price_cny = row.purchase_price_cny if row.purchase_price_cny
    cost.freight_to_by_cny = row.freight_to_by_cny if row.freight_to_by_cny
    apply_default_customs!(cost)

    unless cost.new_record? || cost.changed?
      stdout.puts "UNCHANGED row #{row.source_row}: #{row.sku_code}"
      result.unchanged += 1
      return
    end

    changed_fields = cost.changes.keys.sort.join(", ")
    prefix = dry_run ? "DRY[#{action}]" : action.to_s.upcase
    stdout.puts "#{prefix} row #{row.source_row}: #{row.sku_code} " \
                "effective_on=#{cost.effective_on} (#{changed_fields})"
    cost.save! unless dry_run
    result[action] += 1
  end

  def target_cost_record(sku_code, existing)
    return [ Ec::SkuCost.new(sku_code: sku_code, effective_on: today), :created ] unless existing
    return [ existing, :updated_in_place ] if existing.effective_on == today
    return [ existing, :updated_in_place ] unless cost_complete?(existing)

    [ existing.dup.tap { |copy| copy.effective_on = today }, :versioned ]
  end

  def cost_complete?(cost)
    cost.purchase_price_cny.present? &&
      cost.freight_to_by_cny.present? &&
      cost.customs_misc_cny.present? &&
      cost.customs_duty_rate.present? &&
      cost.import_vat_rate.present?
  end

  def apply_default_customs!(cost)
    if cost.customs_misc_cny.blank? && cost.purchase_price_cny.present?
      cost.customs_misc_cny = (cost.purchase_price_cny * DEFAULT_CUSTOMS_MISC_RATE).round(4)
    end
    cost.customs_duty_rate = DEFAULT_CUSTOMS_DUTY_RATE if cost.customs_duty_rate.blank?
    cost.import_vat_rate = DEFAULT_IMPORT_VAT_RATE if cost.import_vat_rate.blank?
  end
end

if $PROGRAM_NAME == __FILE__
  xlsx_path = ARGV.first.presence || SkuCostsFromLogisticsXlsxImport::DEFAULT_XLSX_PATH
  SkuCostsFromLogisticsXlsxImport.new(xlsx_path: xlsx_path).call
end
