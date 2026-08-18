class BbSpuSkuBatchImport
  DEVELOPER_NAME = "梁珊毓"
  SUPPLIER_NAME = "白沟新城宇隆箱包厂"
  EXPECTED_ARRIVAL_ON = Date.new(2026, 9, 28)

  IMPORT_ROWS = [
    [2, "BB001", "BB001-BK", 27, 200, "37*36*8cm", 0.35, "58*38*50cm", 10.35, 25],
    [3, "BB001", "BB001-BN", 27, 100, "37*36*8cm", 0.35, "58*38*50cm", 10.35, 25],
    [4, "BB001", "BB001-CF", 27, 100, "37*36*8cm", 0.35, "58*38*50cm", 10.35, 25],
    [5, "BB002", "BB002-BK", 41, 200, "40*29*12cm", 0.7, "70*60*50cm", 16.45, 20],
    [6, "BB002", "BB002-EY", 41, 200, "40*29*12cm", 0.7, "70*60*50cm", 16.45, 20],
    [7, "BB002", "BB002-CF", 41, 200, "40*29*12cm", 0.7, "70*60*50cm", 16.45, 20],
    [8, "BB003", "BB003-BK", 27, 200, "36*33*6cm", 0.35, "60*60*40cm", 10.35, 25],
    [9, "BB003", "BB003-CF", 27, 200, "36*33*6cm", 0.35, "60*60*40cm", 10.35, 25],
    [10, "BB004-BN", "BB004-BN", 27, 500, "53*37*2cm", 0.5, "58*50*38cm", 15.1, 25],
    [11, "BB005", "BB005-BK", 25, 200, "22*24*3cm", 0.55, "58*50*38cm", 23.05, 40],
    [12, "BB005", "BB005-BE", 25, 200, "22*24*3cm", 0.55, "58*50*38cm", 23.05, 40],
    [13, "BB006", "BB006-BK", 35, 300, "42*32*5cm", 0.55, "60*60*40cm", 14.55, 25],
    [14, "BB006", "BB006-CF", 35, 200, "42*32*5cm", 0.55, "60*60*40cm", 14.55, 25],
    [15, "BB007", "BB007-BK", 30, 100, "27*24*12cm", 0.55, "58*50*38cm", 15.05, 25],
    [16, "BB007", "BB007-CF", 30, 100, "27*24*12cm", 0.55, "58*50*38cm", 15.05, 25],
    [17, "BB008", "BB008-BK", 27, 200, "30*37*3cm", 0.3, "58*50*38cm", 9.45, 25],
    [18, "BB008", "BB008-CF", 27, 300, "30*37*3cm", 0.3, "58*50*38cm", 9.45, 25],
    [19, "BB009", "BB009-BK", 30, 200, "25*26*12cm", 0.7, "58*50*38cm", 14.85, 20],
    [20, "BB009", "BB009-CF", 30, 200, "25*26*12cm", 0.7, "58*50*38cm", 14.85, 20],
    [21, "BB010", "BB010-BK", 30, 200, "29*37*12cm", 0.45, "60*60*40cm", 13.05, 25],
    [22, "BB010", "BB010-CF", 30, 200, "29*37*12cm", 0.45, "60*60*40cm", 13.05, 25],
    [23, "BB011", "BB011-BK", 22, 300, "42*35*3cm", 0.5, "62*52*40cm", 27.3, 50],
    [24, "BB011", "BB011-CF", 22, 100, "42*35*3cm", 0.5, "62*52*40cm", 27.3, 50]
  ].map do |source_row, master_sku_code, sku_code, cost, po_quantity, inner_size, inner_weight, outer_size, outer_weight, outer_box_pcs|
    {
      source_row: source_row,
      master_sku_code: master_sku_code,
      sku_code: sku_code,
      purchase_unit_price_cny: cost,
      purchased_quantity: po_quantity,
      inner_size: inner_size,
      inner_box_weight_kg: inner_weight,
      outer_size: outer_size,
      outer_box_weight_kg: outer_weight,
      outer_box_pcs: outer_box_pcs
    }.freeze
  end.freeze

  Result = Struct.new(:master_skus, :skus, :dimensions, :batches, keyword_init: true)

  def initialize(rows: IMPORT_ROWS, env: ENV, stdout: $stdout)
    @rows = rows
    @dry_run = !ActiveModel::Type::Boolean.new.cast(env.fetch("APPLY", false))
    @stdout = stdout
  end

  def call
    developer = find_unique_user!
    supplier = Ec::Supplier.find_by!(name: SUPPLIER_NAME)
    result = Result.new(master_skus: 0, skus: 0, dimensions: 0, batches: 0)

    stdout.puts "BB SPU/SKU/batch import (#{dry_run ? 'dry run' : 'apply'})"

    ApplicationRecord.transaction do
      rows.each { |row| import_row!(row, developer:, supplier:, result:) }
      raise ActiveRecord::Rollback if dry_run
    end

    master_sku_count = rows.map { |row| normalize_code(row.fetch(:master_sku_code)) }.uniq.size
    stdout.puts "Processed: #{master_sku_count} SPUs, #{result.skus} SKUs, " \
                "#{result.dimensions} dimensions, #{result.batches} batches"
    stdout.puts "No data changed. Run with APPLY=1 to write." if dry_run
    result
  end

  private

  attr_reader :rows, :dry_run, :stdout

  def find_unique_user!
    users = User.where(name: DEVELOPER_NAME).to_a
    raise "User name #{DEVELOPER_NAME.inspect} was not found" if users.empty?
    raise "User name #{DEVELOPER_NAME.inspect} is not unique" if users.many?

    users.first
  end

  def import_row!(row, developer:, supplier:, result:)
    master_sku = find_or_create_master_sku!(row.fetch(:master_sku_code))
    sku = find_or_create_sku!(row.fetch(:sku_code), master_sku)
    replace_developer!(sku, developer)
    upsert_dimensions!(sku.sku_code, row)
    upsert_batch!(sku.sku_code, supplier, row)

    result.master_skus += 1
    result.skus += 1
    result.dimensions += 1
    result.batches += 1
    stdout.puts "#{dry_run ? 'DRY' : 'UPSERT'} row #{row.fetch(:source_row)}: " \
                "#{master_sku.master_sku_code} -> #{sku.sku_code}"
  end

  def find_or_create_master_sku!(code)
    normalized = normalize_code(code)
    Ec::MasterSku.find_or_create_by!(master_sku_code: normalized) do |master_sku|
      master_sku.product_name = normalized
      master_sku.is_active = true
    end
  end

  def find_or_create_sku!(code, master_sku)
    normalized = normalize_code(code)
    sku = Ec::Sku.with_deleted.find_or_initialize_by(sku_code: normalized)
    raise "SKU #{normalized} is soft-deleted" if sku.persisted? && sku.deleted?
    if sku.master_sku.present? && sku.master_sku != master_sku
      raise "SKU #{normalized} already belongs to SPU #{sku.master_sku.master_sku_code}"
    end

    sku.master_sku ||= master_sku
    sku.product_name ||= normalized
    sku.is_active = true if sku.new_record?
    sku.save! if sku.new_record? || sku.changed?
    sku
  end

  def replace_developer!(sku, developer)
    sku.developer_assignments.where.not(user_id: developer.id).delete_all
    sku.developer_assignments.find_or_create_by!(user: developer)
  end

  def upsert_dimensions!(sku_code, row)
    inner_length, inner_width, inner_height = parse_dimensions!(row.fetch(:inner_size), row.fetch(:source_row))
    outer_length, outer_width, outer_height = parse_dimensions!(row.fetch(:outer_size), row.fetch(:source_row))
    dimensions = Ec::SkuDimension.find_or_initialize_by(sku_code: sku_code)
    dimensions.assign_attributes(
      inner_length_cm: inner_length,
      inner_width_cm: inner_width,
      inner_height_cm: inner_height,
      inner_box_weight_kg: row.fetch(:inner_box_weight_kg),
      outer_length_cm: outer_length,
      outer_width_cm: outer_width,
      outer_height_cm: outer_height,
      outer_box_weight_kg: row.fetch(:outer_box_weight_kg),
      outer_box_pcs: row.fetch(:outer_box_pcs)
    )
    dimensions.save! if dimensions.new_record? || dimensions.changed?
  end

  def upsert_batch!(sku_code, supplier, row)
    batch = Ec::SkuBatch.find_or_initialize_by(batch_code: batch_code(row))
    if batch.persisted? && batch.sku_code != sku_code
      raise "Batch #{batch.batch_code} already belongs to SKU #{batch.sku_code}"
    end

    batch.assign_attributes(
      sku_code: sku_code,
      supplier: supplier,
      batch_type: :normal,
      status: "ordered",
      purchased_quantity: row.fetch(:purchased_quantity),
      received_quantity: 0,
      purchase_unit_price_cny: row.fetch(:purchase_unit_price_cny),
      expected_arrival_on: EXPECTED_ARRIVAL_ON
    )
    batch.save! if batch.new_record? || batch.changed?
  end

  def batch_code(row)
    "BB-DATA-R#{row.fetch(:source_row)}-#{normalize_code(row.fetch(:sku_code))}"
  end

  def parse_dimensions!(value, source_row)
    match = value.to_s.strip.match(/\A(\d+(?:\.\d+)?)\s*[x*]\s*(\d+(?:\.\d+)?)\s*[x*]\s*(\d+(?:\.\d+)?)\s*cm\z/i)
    raise "Invalid dimensions at source row #{source_row}: #{value.inspect}" unless match

    match.captures.map { |number| BigDecimal(number) }
  end

  def normalize_code(value)
    value.to_s.strip.upcase
  end
end

BbSpuSkuBatchImport.new.call if $PROGRAM_NAME == __FILE__
