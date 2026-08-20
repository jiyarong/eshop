# frozen_string_literal: true

# Usage:
#   bundle exec rails runner script/import_sku_product_info_from_csv.rb /path/to/sku_info.csv
#   APPLY=1 bundle exec rails runner script/import_sku_product_info_from_csv.rb /path/to/sku_info.csv
#
# Column A must contain the SKU code and column B the product info. Product info
# may span multiple lines, contain unescaped double quotes, or omit surrounding
# quotes. The default is a dry run.

class SkuProductInfoCsvImport
  DEFAULT_CSV_PATH = Rails.root.join("tmp", "sku_info.csv")
  RECORD_START = /\A([A-Za-z][A-Za-z0-9_-]*),("?)(.*)\z/m

  Row = Data.define(:source_line, :sku_code, :product_info)
  Result = Struct.new(:updated, :unchanged, :missing_sku, :blank_product_info, :total, keyword_init: true)

  def initialize(csv_path: DEFAULT_CSV_PATH, env: ENV, stdout: $stdout)
    @csv_path = Pathname(csv_path)
    @dry_run = !ActiveModel::Type::Boolean.new.cast(env.fetch("APPLY", false))
    @stdout = stdout
  end

  def call
    rows = parse_rows
    result = Result.new(updated: 0, unchanged: 0, missing_sku: 0, blank_product_info: 0, total: rows.size)

    stdout.puts "SKU product info import"
    stdout.puts "Source: #{csv_path}"
    stdout.puts "Dry run: #{dry_run ? "yes" : "no"}"
    stdout.puts "Rows found: #{result.total}"

    ApplicationRecord.transaction do
      rows.each { |row| import_row(row, result) }
    end

    stdout.puts "Updated: #{result.updated}"
    stdout.puts "Unchanged: #{result.unchanged}"
    stdout.puts "Missing SKU: #{result.missing_sku}"
    stdout.puts "Blank product info: #{result.blank_product_info}"
    stdout.puts "DRY_RUN=1, no data changed. Set APPLY=1 to write." if dry_run
    result
  end

  private

  attr_reader :csv_path, :dry_run, :stdout

  def parse_rows
    raise ArgumentError, "CSV file not found: #{csv_path}" unless csv_path.file?

    content = csv_path.binread.force_encoding(Encoding::UTF_8)
    raise ArgumentError, "CSV is not valid UTF-8: #{csv_path}" unless content.valid_encoding?

    content = content.delete_prefix("\uFEFF").gsub(/\r\n?/, "\n")
    rows = []
    current = nil

    content.each_line.with_index(1) do |line, line_number|
      match = line.match(RECORD_START)
      if match
        rows << build_row(current) if current
        current = {
          source_line: line_number,
          sku_code: match[1],
          quoted: match[2] == '"',
          product_info: +match[3]
        }
      elsif current
        current[:product_info] << line
      elsif line.strip.present?
        raise ArgumentError, "Invalid content before the first record at line #{line_number}"
      end
    end

    rows << build_row(current) if current
    raise ArgumentError, "No records found in #{csv_path}" if rows.empty?

    duplicate = rows.group_by(&:sku_code).find { |_sku_code, sku_rows| sku_rows.many? }
    if duplicate
      sku_code, sku_rows = duplicate
      lines = sku_rows.map(&:source_line).join(", ")
      raise ArgumentError, "Duplicate SKU #{sku_code} at lines #{lines}"
    end

    rows
  end

  def build_row(raw_row)
    product_info = raw_row.fetch(:product_info).delete_suffix("\n")
    product_info = product_info.delete_suffix('"') if raw_row.fetch(:quoted)

    sku_code = raw_row.fetch(:sku_code).strip.upcase
    raise ArgumentError, "SKU is blank at line #{raw_row.fetch(:source_line)}" if sku_code.blank?

    Row.new(
      source_line: raw_row.fetch(:source_line),
      sku_code: sku_code,
      product_info: product_info
    )
  end

  def import_row(row, result)
    if row.product_info.blank?
      stdout.puts "SKIP line #{row.source_line}: product info is blank for #{row.sku_code}"
      result.blank_product_info += 1
      return
    end

    sku = Ec::Sku.find_by(sku_code: row.sku_code)
    unless sku
      stdout.puts "SKIP line #{row.source_line}: SKU not found: #{row.sku_code}"
      result.missing_sku += 1
      return
    end

    if sku.product_info == row.product_info
      stdout.puts "UNCHANGED line #{row.source_line}: #{row.sku_code}"
      result.unchanged += 1
      return
    end

    stdout.puts "#{dry_run ? "DRY" : "UPDATE"} line #{row.source_line}: #{row.sku_code} " \
                "(#{sku.product_info.to_s.length} -> #{row.product_info.length} characters)"
    sku.update!(product_info: row.product_info) unless dry_run
    result.updated += 1
  end
end

if $PROGRAM_NAME == __FILE__
  csv_path = ARGV.first.presence || SkuProductInfoCsvImport::DEFAULT_CSV_PATH
  SkuProductInfoCsvImport.new(csv_path: csv_path).call
end
