require "test_helper"
require "tmpdir"

class Ec::SkuProfitGoogleSheetImporterTest < ActiveSupport::TestCase
  class FakeReader
    def initialize(rows_by_key, formulas: {})
      @rows_by_key = rows_by_key
      @formulas = formulas
    end

    def read(config)
      @rows_by_key.fetch(config.fetch(:key), [ [ "header" ] ])
    end

    def formula(config, row_number, column_index)
      @formulas.dig(config.fetch(:key), row_number, column_index)
    end
  end

  setup do
    @token = SecureRandom.hex(5).upcase
    @skus = []
  end

  teardown do
    sku_ids = @skus.map(&:id)
    sku_codes = @skus.map(&:sku_code)
    version_ids = Ec::SkuProfitVersion.where(sku_id: sku_ids).pluck(:id)
    context_ids = Ec::SkuProfitVersionContext.where(sku_profit_version_id: version_ids).pluck(:id)
    dimension_ids = Ec::SkuDimension.where(sku_code: sku_codes).pluck(:id)

    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersionContext", record_id: context_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: version_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuDimension", record_id: dimension_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: sku_ids).delete_all
    Ec::SkuProfitVersionContext.where(id: context_ids).delete_all
    Ec::SkuProfitVersion.where(id: version_ids).delete_all
    Ec::SkuDimension.where(id: dimension_ids).delete_all
    Ec::Sku.unscoped.where(id: sku_ids).delete_all
  end

  test "normalizes case whitespace unicode dashes and punctuation" do
    normalize = Ec::SkuProfitGoogleSheetImporter::SkuCodeNormalizer

    assert_equal "KJ217GD", normalize.call("  kj\u00A0- 217—gd\u200B ")
    assert_equal normalize.call("CYQ_97 / WT"), normalize.call("cyq-97-wt")
  end

  test "reads target rows from a local XLSX export" do
    Dir.mktmpdir("sku-profit-import") do |directory|
      path = File.join(directory, "source.xlsx")
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "ПРОДАЖА (WB)") do |sheet|
        sheet.add_row [ "SKU", "Name", "Unused" ]
        sheet.add_row [ "LOCAL-1", "Product", nil, nil, 12.5 ]
      end
      package.serialize(path)

      rows = Ec::SkuProfitGoogleSheetImporter::XlsxReader.new(path:).read(
        Ec::SkuProfitGoogleSheetImporter::TAB_CONFIGS.first
      )

      assert_equal "SKU", rows[0][0]
      assert_equal "LOCAL-1", rows[1][0]
      assert_equal 12.5.to_d, rows[1][4]
    end
  end

  test "expands relative references in shared XLSX formulas" do
    reader = Ec::SkuProfitGoogleSheetImporter::XlsxReader.allocate

    translated = reader.send(:translate_formula, "AA2/AC2+$B$1", from: "AD2", to: "AD35")

    assert_equal "AA35/AC35+$B$1", translated
  end

  test "dry run keeps only the last row for a repeated SKU without writing" do
    sku = create_sku("DUP-#{@token}")
    first = wb_row(" dup - #{@token.downcase} ", company_type: "general", price: 1_000)
    last = wb_row("DUP—#{@token}", company_type: "general", price: 2_000)
    importer = build_importer(wb_general: [ [ "header" ], first, last ])

    assert_no_difference -> { Ec::SkuProfitVersion.count } do
      summary = importer.call

      assert summary.fetch(:ok), summary.inspect
      assert_equal [ sku.sku_code ], summary.fetch(:matched_skus)
      assert_equal 1, summary.fetch(:versions_would_create)
      assert_equal 6, summary.fetch(:contexts_would_create)
      duplicate = summary.fetch(:duplicate_rows_discarded).sole
      assert_equal 2, duplicate.fetch(:discarded_row)
      assert_equal 3, duplicate.fetch(:kept_row)
    end
  end

  test "apply merges three tabs into one version and is idempotent" do
    sku = create_sku("MERGE-#{@token}")
    rows = {
      wb_general: [ [ "header" ], wb_row(sku.sku_code, company_type: "general", price: 1_000, mode: "FBS") ],
      wb_small: [ [ "header" ], wb_row(sku.sku_code.downcase, company_type: "small", price: 2_000, mode: "FBW") ],
      ozon: [ [ "header" ], ozon_row(" merge — #{@token.downcase} ", ru_price: 3_000, by_price: 4_000) ]
    }
    importer = build_importer(rows, dry_run: false)

    assert_difference -> { Ec::SkuProfitVersion.count }, 1 do
      summary = importer.call

      assert summary.fetch(:ok)
      assert_equal 1, summary.fetch(:versions_created)
      assert_equal 6, summary.fetch(:contexts_created)
    end

    version = sku.profit_versions.includes(:contexts).sole
    assert_equal "draft", version.status
    assert_equal 6, version.contexts.size
    assert_equal 1_000.to_d, version.context_for(platform: "wb", market: "ru", delivery_mode: "fbs", warehouse_region: "main", company_type: "general").price_rub
    assert_equal 2_000.to_d, version.context_for(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small").price_rub
    assert_equal 3_000.to_d, version.context_for(platform: "ozon", market: "ru", delivery_mode: "fbo", warehouse_region: "main").price_rub
    assert_equal 4_000.to_d, version.context_for(platform: "ozon", market: "by", delivery_mode: "fbo", warehouse_region: "main").price_rub
    assert_equal 4, version.contexts.count { |context| context.calculation_status == "valid" }
    assert_equal 2, version.contexts.count { |context| context.calculation_status == "incomplete" }

    assert_no_difference -> { Ec::SkuProfitVersion.count } do
      rerun = build_importer(rows, dry_run: false).call
      assert_equal [ { sku_code: sku.sku_code, version_id: version.id } ], rerun.fetch(:skipped_existing_versions)
      assert_equal 0, rerun.fetch(:contexts_created)
    end
  end

  test "apply backfills an older imported version without overwriting existing inputs" do
    sku = create_sku("BACKFILL-#{@token}")
    effective_from = Date.new(2026, 9, 16)
    version = sku.profit_versions.create!(
      name: "Older import",
      status: "draft",
      effective_from:,
      note: "sku-profit-google-sheet-import:v4:#{Ec::SkuProfitGoogleSheetImporter::DEFAULT_SPREADSHEET_ID}:#{effective_from.iso8601}"
    )
    existing = version.contexts.create!(
      platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
      purchase_price_cny: 100, price_rub: 777, exchange_rate_rub_cny: 10,
      length_cm: 10, width_cm: 10, height_cm: 10, logistics_coeff: 1.2, commission_rate: 0.1
    )
    rows = { wb_general: [ [ "header" ], wb_row(sku.sku_code, company_type: "general", price: 9_999) ] }

    summary = build_importer(rows, dry_run: false).call

    assert summary.fetch(:ok)
    assert_equal 0, summary.fetch(:versions_created)
    assert_equal 1, summary.fetch(:versions_updated)
    assert_equal 5, summary.fetch(:contexts_created)
    assert_equal 6, version.reload.contexts.count
    assert_equal 777.to_d, existing.reload.price_rub
  end

  test "system SKU dimensions override different spreadsheet dimensions" do
    sku = create_sku("DIM-#{@token}")
    row = wb_row(sku.sku_code, company_type: "general")
    row[10] = 99
    row[11] = 88
    row[12] = 77

    summary = build_importer({ wb_general: [ [ "header" ], row ] }, dry_run: false).call

    version = sku.profit_versions.includes(:contexts).sole
    context = version.context_for(
      platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general"
    )
    assert_equal 10.to_d, context.length_cm
    assert_equal 10.to_d, context.width_cm
    assert_equal 10.to_d, context.height_cm
    difference = summary.fetch(:dimension_differences).sole
    assert_equal sku.sku_code, difference.fetch(:sku_code)
    assert_equal %w[height_cm length_cm width_cm], difference.fetch(:differences).pluck(:field).map(&:to_s).sort
  end

  test "reverses WB return amortization into the underlying return rate" do
    sku = create_sku("RETURN-#{@token}")
    row = wb_row(sku.sku_code, company_type: "general")

    summary = build_importer({ wb_general: [ [ "header" ], row ] }, dry_run: false).call

    assert summary.fetch(:ok)
    version = sku.profit_versions.includes(:contexts).sole
    context = version.context_for(
      platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general"
    )
    assert_in_delta BigDecimal("0.1666666667"), context.return_rate, BigDecimal("0.0000000001")
  end

  test "imports the authoritative WB fixed return base for a small company" do
    sku = create_sku("SMALL-RETURN-#{@token}")
    row = wb_row(sku.sku_code, company_type: "small")

    summary = build_importer({ wb_small: [ [ "header" ], row ] }, dry_run: false).call

    assert summary.fetch(:ok)
    version = sku.profit_versions.includes(:contexts).sole
    context = version.context_for(
      platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small"
    )
    assert_equal 50.to_d, context.wb_fixed_return_base_rub
    assert_nil context.logistics_tax_rate
  end

  test "imports Ozon formula variants from the selected total-cost columns" do
    sku = create_sku("OZON-FORMULA-#{@token}")
    row = ozon_row(sku.sku_code, ru_price: 3_000, by_price: 4_000)
    row[9] = 100
    row[11] = 80
    row[12] = 20
    row[15] = 4
    row[19] = 5
    row[20] = BigDecimal("126.111111111111")
    row[28] = BigDecimal("30.69")
    formulas = {
      ozon: {
        2 => {
          28 => "=AH2*10%+6.9/AG2",
          36 => "=G2+P2+V2+Z2+AB2+AC2-F2",
          37 => "=G2+V2+AB2+AC2+AJ2+AA2"
        }
      }
    }
    reader = FakeReader.new({ ozon: [ [ "header" ], row ] }, formulas: formulas)
    importer = Ec::SkuProfitGoogleSheetImporter.new(
      reader:,
      effective_from: Date.new(2026, 9, 16),
      version_name: "Formula variant #{@token}",
      dry_run: false
    )

    summary = importer.call

    assert summary.fetch(:ok)
    version = sku.profit_versions.includes(:contexts).sole
    ru = version.context_for(platform: "ozon", market: "ru", delivery_mode: "fbo", warehouse_region: "main")
    by = version.context_for(platform: "ozon", market: "by", delivery_mode: "fbo", warehouse_region: "main")
    assert_equal 100.to_d, ru.outbound_logistics_rub
    assert_equal 80.to_d, ru.return_logistics_rub
    assert_in_delta 0.1.to_d, ru.return_rate, BigDecimal("0.0000000001")
    assert_nil ru.return_amortization_factor_override
    assert_in_delta 1.to_d / 9, ru.ozon_warehouse_rate, BigDecimal("0.0000000001")
    assert_equal 4.to_d, ru.cross_docking_cny
    assert_equal 6.9.to_d, ru.advertising_fixed_rub
    assert_in_delta BigDecimal("0.1"), ru.advertising_rate, BigDecimal("0.0000000001")
    assert_equal 0.to_d, ru.ozon_import_vat_cost_rate
    assert_equal 0.to_d, by.cross_docking_cny
  end

  test "reports unknown codes and normalized SKU collisions instead of guessing" do
    first = create_sku("COL-#{@token}")
    second = create_sku("COL#{@token}")
    rows = {
      wb_general: [
        [ "header" ],
        wb_row("UNKNOWN-#{@token}", company_type: "general"),
        wb_row("col #{@token.downcase}", company_type: "general")
      ]
    }

    summary = build_importer(rows).call

    assert_not summary.fetch(:ok)
    assert_equal 1, summary.fetch(:unmatched_rows).size
    assert_equal 1, summary.fetch(:ambiguous_rows).size
    collision_codes = summary.fetch(:ambiguous_rows).sole.fetch(:details).flat_map(&:last)
    assert_equal [ first.sku_code, second.sku_code ].sort, collision_codes.sort
    assert_equal 0, summary.fetch(:versions_would_create)
  end

  test "detects normalized collisions when the SKU is embedded in descriptive text" do
    create_sku("EM-BED-#{@token}")
    create_sku("EMBED#{@token}")
    rows = {
      wb_general: [ [ "header" ], wb_row("Product em bed #{@token.downcase} FBO", company_type: "general") ]
    }

    summary = build_importer(rows).call

    assert_not summary.fetch(:ok)
    assert_equal 1, summary.fetch(:ambiguous_rows).size
    assert_equal 0, summary.fetch(:versions_would_create)
  end

  test "a source read failure aborts before any writes" do
    create_sku("READ-#{@token}")
    reader = Object.new
    reader.define_singleton_method(:read) { |_config| raise IOError, "network unavailable" }
    importer = Ec::SkuProfitGoogleSheetImporter.new(
      reader:,
      effective_from: Date.new(2026, 9, 16),
      dry_run: false
    )

    assert_no_difference -> { Ec::SkuProfitVersion.count } do
      summary = importer.call

      assert_not summary.fetch(:ok)
      assert_equal "source_read", summary.fetch(:failures).sole.fetch(:stage)
    end
  end

  test "invalid data for one SKU does not prevent another SKU from importing" do
    valid_sku = create_sku("GOOD-#{@token}")
    invalid_sku = create_sku("BAD-#{@token}")
    invalid_row = wb_row(invalid_sku.sku_code, company_type: "general")
    invalid_row[30] = "not-a-rate"
    rows = {
      wb_general: [
        [ "header" ],
        wb_row(valid_sku.sku_code, company_type: "general"),
        invalid_row
      ]
    }

    summary = build_importer(rows, dry_run: false).call

    assert_not summary.fetch(:ok)
    assert_equal 1, summary.fetch(:invalid_rows).size
    assert_equal invalid_sku.sku_code, summary.fetch(:invalid_rows).sole.fetch(:sku_code)
    assert_equal 1, summary.fetch(:versions_created)
    assert valid_sku.profit_versions.exists?
    assert_not invalid_sku.profit_versions.exists?
  end

  private

  def create_sku(code)
    sku = Ec::Sku.create!(sku_code: code, product_name: "Import test", is_active: true)
    Ec::SkuDimension.create!(
      sku_code: sku.sku_code,
      inner_length_cm: 10,
      inner_width_cm: 10,
      inner_height_cm: 10
    )
    @skus << sku
    sku
  end

  def build_importer(rows = nil, dry_run: true, **rows_by_key)
    source = rows || rows_by_key
    Ec::SkuProfitGoogleSheetImporter.new(
      reader: FakeReader.new(source),
      effective_from: Date.new(2026, 9, 16),
      version_name: "Test initial import #{@token}",
      dry_run:
    )
  end

  def wb_row(code, company_type:, price: 1_500, mode: "FBO")
    row = Array.new(53)
    exchange_index = company_type == "general" ? 28 : 29
    revenue_index = company_type == "general" ? 29 : 30
    commission_index = company_type == "general" ? 30 : 31
    row[0] = code
    row[1] = "Product #{mode}"
    row[4] = 100
    row[5] = 10
    row[6] = 5
    row[7] = 10
    row[8] = 22
    row[9] = 147
    row[10] = 10
    row[11] = 10
    row[12] = 10
    row[16] = 1.2
    row[17] = 3
    row[18] = 12
    row[19] = 2.4
    row[21] = 1
    row[22] = 3
    row[23] = 5
    row[24] = 0
    row[25] = 2
    row[26] = price
    row[27] = mode
    row[exchange_index] = 10
    row[revenue_index] = price.to_d / 10
    row[commission_index] = 0.1
    row
  end

  def ozon_row(code, ru_price:, by_price:)
    row = Array.new(53)
    row[0] = code
    row[1] = 100
    row[2] = 10
    row[3] = 5
    row[4] = 10
    row[5] = 22
    row[6] = 147
    row[7] = 1
    row[16] = 20
    row[17] = 10
    row[19] = 5
    row[24] = 0.1
    row[27] = ru_price.to_d / 10 * BigDecimal("0.02")
    row[28] = ru_price.to_d / 10 * BigDecimal("0.05")
    row[29] = 0
    row[30] = ru_price
    row[31] = by_price
    row[32] = 10
    row[33] = ru_price.to_d / 10
    row[34] = by_price.to_d / 10
    row
  end
end
