require "test_helper"
require "tmpdir"

class Ec::SkuProfitPricingSheetImporterTest < ActiveSupport::TestCase
  Importer = Ec::SkuProfitPricingSheetImporter

  class FakeReader
    def initialize(rows_by_key)
      @rows_by_key = rows_by_key
    end

    def read(config)
      @rows_by_key.fetch(config.fetch(:key), [ [ "header" ] ])
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

  test "imports only the price: WB mode from the label, Ozon commission base from the RU price and buyer paid from the BY price" do
    wb = create_sku("WBP-#{@token}")
    ozon = create_sku("OZP-#{@token}")
    rows = {
      wb_small: [
        [ "header" ],
        wb_row("#{wb.sku_code}\nFBS", price: 14_700, exchange: 12.5, commission: 0.235)
      ],
      ozon: [ [ "header" ], ozon_row(ozon.sku_code, ru_price: 10_800, by_price: 10_200) ]
    }

    summary = build_importer(rows, dry_run: false).call

    assert summary.fetch(:ok), summary.inspect
    wb_context = wb.profit_versions.sole.context_for(
      platform: "wb", market: "ru", delivery_mode: "fbs", warehouse_region: "main", company_type: "small"
    )
    assert_equal 14_700.to_d, wb_context.commission_base_price_rub
    # Nothing actual and no standard rate exist for a fresh SKU: the sheet fills the gap, visibly.
    assert_equal 0.235.to_d, wb_context.commission_rate
    assert_equal 12.5.to_d, wb_context.exchange_rate_rub_cny

    ozon_version = ozon.profit_versions.sole
    ru = ozon_version.context_for(platform: "ozon", market: "ru", delivery_mode: "fbo", warehouse_region: "main")
    by = ozon_version.context_for(platform: "ozon", market: "by", delivery_mode: "fbo", warehouse_region: "main")
    assert_equal 10_800.to_d, ru.commission_base_price_rub
    assert_equal 10_800.to_d, by.commission_base_price_rub
    assert_equal 10_200.to_d, by.buyer_paid_price_rub
    assert_nil ru.buyer_paid_price_rub
    assert_equal "draft", ozon_version.status
  end

  test "dry run writes nothing and a second apply does not duplicate the version" do
    sku = create_sku("RUN-#{@token}")
    rows = { wb_general: [ [ "header" ], wb_row(sku.sku_code, price: 9_000) ] }

    assert_no_difference -> { Ec::SkuProfitVersion.count } do
      summary = build_importer(rows).call
      assert_equal 1, summary.fetch(:versions_would_create)
    end

    build_importer(rows, dry_run: false).call
    assert_equal 1, sku.profit_versions.count

    again = build_importer(rows, dry_run: false).call
    assert_equal 1, sku.profit_versions.count
    assert_equal 1, again.fetch(:skipped_existing_versions).size
  end

  test "reports rows that cannot be imported and keeps the last of several rows for one context" do
    sku = create_sku("DUP-#{@token}")
    rows = {
      wb_small: [
        [ "header" ],
        wb_row("#{sku.sku_code} FBO Ryazan", price: 12_000),
        wb_row("#{sku.sku_code} FBO Novgorod", price: 13_960),
        wb_row("UNKNOWN-#{@token} FBO", price: 1_000),
        wb_row("", price: 2_000),
        wb_row("#{sku.sku_code} FBS", price: nil)
      ]
    }

    summary = build_importer(rows).call

    assert_equal 1, summary.fetch(:unmatched_rows).size
    assert_equal 1, summary.fetch(:rows_without_sku).size
    assert_equal 1, summary.fetch(:rows_without_price).size
    duplicate = summary.fetch(:duplicate_rows_discarded).sole
    assert_equal 12_000.to_d, duplicate.dig(:discarded, :price)
    assert_equal 13_960.to_d, duplicate.dig(:kept, :price)
    price = summary.fetch(:contexts).find do |context|
      context[:priced] && context.dig(:context, "delivery_mode") == "fbo"
    end
    assert_equal 13_960.0, price.fetch(:commission_base_price_rub)
  end

  test "uses the four-week actual averages and the standard commission before the sheet" do
    sku = create_sku("ACT-#{@token}")
    rows = { wb_general: [ [ "header" ], wb_row(sku.sku_code, price: 9_000, commission: 0.3) ] }
    logistics = {
      outbound: { average_rub: BigDecimal("210.5") },
      return: { average_rub: BigDecimal("48") },
      cross_dock: {}
    }
    commission = { rates: [ { rate: "0.185" } ], errors: {} }
    storage = { storage: { average_rub: BigDecimal("26") } }
    advertising = { rate: BigDecimal("0.07") }
    return_rate = { return_rate: { rate: BigDecimal("0.12") } }
    selling = { buyer_paid_price: { average_rub: BigDecimal("8800") } }
    acquiring = { acquiring: { rate: BigDecimal("0.0291") } }

    summary = with_stubbed_queries(logistics:, commission:, storage:, advertising:, return_rate:, selling:, acquiring:) do
      build_importer(rows, dry_run: false).call
    end

    assert summary.fetch(:ok), summary.inspect
    context = sku.profit_versions.sole.context_for(
      platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general"
    )
    assert_equal 210.5.to_d, context.outbound_logistics_rub
    assert_equal 48.to_d, context.return_logistics_rub
    assert_equal 0.12.to_d, context.return_rate
    assert_equal 0.185.to_d, context.commission_rate
    assert_equal 0.07.to_d, context.advertising_rate
    assert_equal 8_800.to_d, context.buyer_paid_price_rub
    assert_equal 0.0291.to_d, context.acquiring_rate
    assert_equal 9_000.to_d, context.commission_base_price_rub
    assert_in_delta 2, context.storage_cny.to_f, 0.001
    reported = summary.fetch(:contexts).find { |entry| entry[:priced] }
    assert_equal "standard", reported.dig(:sources, "commission_rate")
    assert_equal "actual_4w", reported.dig(:sources, "outbound_logistics_rub")
  end

  test "without acquiring data the standard acquiring rate of the scenario is kept" do
    sku = create_sku("ACQ-#{@token}")
    rows = { wb_general: [ [ "header" ], wb_row(sku.sku_code, price: 9_000) ], wb_small: [ [ "header" ], wb_row(sku.sku_code, price: 9_000) ] }

    summary = build_importer(rows, dry_run: false).call

    version = sku.profit_versions.sole
    general = version.context_for(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general")
    small = version.context_for(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small")
    assert_equal 0.015.to_d, general.acquiring_rate
    assert_equal 0.031.to_d, small.acquiring_rate
    assert_equal "default", summary.fetch(:contexts).find { |entry| entry[:priced] }.dig(:sources, "acquiring_rate")
  end

  test "a missing or ambiguous standard commission falls back to the sheet and says why" do
    sku = create_sku("COM-#{@token}")
    rows = { wb_general: [ [ "header" ], wb_row(sku.sku_code, price: 9_000, commission: 0.3) ] }
    commission = { rates: [ { rate: "0.15" }, { rate: "0.2" } ], errors: {} }

    summary = with_stubbed_queries(commission:) { build_importer(rows).call }

    reported = summary.fetch(:contexts).find { |entry| entry[:priced] }
    assert_equal "sheet", reported.dig(:sources, "commission_rate")
    assert_match(/multiple_standard_rates/, reported.dig(:sources, :commission_gap))
    assert summary.fetch(:gaps).fetch("commission_rate").any? { |entry| entry.include?(sku.sku_code) }
  end

  test "an advertising rate of 100 percent or more is not applied" do
    sku = create_sku("ADV-#{@token}")
    rows = { wb_general: [ [ "header" ], wb_row(sku.sku_code, price: 9_000) ] }

    summary = with_stubbed_queries(advertising: { rate: BigDecimal("1.18") }) do
      build_importer(rows).call
    end

    assert_empty summary.fetch(:contexts).select { |entry| entry[:priced] }.flat_map { |entry| entry[:errors] }
    reported = summary.fetch(:contexts).find { |entry| entry[:priced] }
    assert_equal "none", reported.dig(:sources, "advertising_rate")
    assert_match(/advertising/, reported.dig(:sources, :unavailable).join)
  end

  test "reads the known LD-for-LDD typo as the LDD SKU and reports it, but only when the code matches nothing" do
    lamp = create_sku("LDD#{@token.first(3).tr('A-F', '0-5')}")
    number = lamp.sku_code.delete_prefix("LDD")
    rows = {
      wb_small: [ [ "header" ], wb_row("LD#{number}-BK FBS", price: 6_120), wb_row("LDD#{number} FBO", price: 7_000) ]
    }
    create_sku("LDD#{number}-BK")

    summary = build_importer(rows).call

    assert_empty summary.fetch(:unmatched_rows)
    aliased = summary.fetch(:aliased_rows).sole
    assert_equal "LDD#{number}-BK FBS", aliased.fetch(:read_as)
    assert_equal [ "LDD#{number}-BK" ], aliased.fetch(:sku_codes)
    assert_equal [ "LDD#{number}", "LDD#{number}-BK" ].sort, summary.fetch(:matched_skus)
  end

  test "reads the tabs from a JSON dump" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "tabs.json")
      File.write(path, JSON.generate({ Importer::TAB_CONFIGS.first.fetch(:title) => [ [ "header" ], [ "x" ] ] }))

      rows = Importer::JsonReader.new(path:).read(Importer::TAB_CONFIGS.first)

      assert_equal [ [ "header" ], [ "x" ] ], rows
    end
  end

  private

  def create_sku(code)
    sku = Ec::Sku.create!(sku_code: code, product_name: "Pricing import test", is_active: true)
    Ec::SkuDimension.create!(sku_code: sku.sku_code, inner_length_cm: 10, inner_width_cm: 10, inner_height_cm: 10)
    @skus << sku
    sku
  end

  def build_importer(rows, dry_run: true)
    Importer.new(
      reader: FakeReader.new(rows),
      effective_from: Date.new(2026, 10, 14),
      today: Date.new(2026, 10, 14),
      version_name: "Pricing import #{@token}",
      dry_run:,
      sku_scope: Ec::Sku.where(id: @skus.map(&:id))
    )
  end

  def wb_row(code, price: 1_500, exchange: 13, commission: 0.2)
    row = Array.new(44)
    row[0] = code
    row[1] = "Product"
    row[4] = 100
    row[5] = 10
    row[6] = 2
    row[7] = 10
    row[8] = 22
    row[10] = 10
    row[11] = 10
    row[12] = 10
    row[16] = 1.55
    row[26] = price
    row[28] = exchange
    row[29] = exchange
    row[30] = commission
    row[31] = commission
    row
  end

  def ozon_row(code, ru_price:, by_price:)
    row = Array.new(65)
    row[0] = code
    row[1] = 100
    row[2] = 10
    row[3] = 2
    row[4] = 10
    row[5] = 22
    row[16] = 245
    row[17] = 245
    row[19] = 25
    row[24] = 0.075
    row[30] = ru_price
    row[31] = by_price
    row[32] = 13
    row
  end

  # Replaces the actual-data queries with canned payloads (nil keeps the real, empty-DB answer).
  def with_stubbed_queries(logistics: nil, commission: nil, storage: nil, advertising: nil, return_rate: nil, selling: nil,
    acquiring: nil)
    stubs = {
      Ec::SkuActualLogisticsQuery => logistics,
      Ec::SkuOfficialCommissionRateQuery => commission,
      Ec::SkuActualStorageQuery => storage,
      Ec::SkuActualAdvertisingQuery => advertising,
      Ec::SkuActualReturnRateQuery => return_rate,
      Ec::SkuActualSellingPriceQuery => selling,
      Ec::SkuActualAcquiringQuery => acquiring
    }.select { |_klass, payload| payload }
    originals = stubs.keys.index_with { |klass| klass.method(:run) }
    stubs.each do |klass, payload|
      klass.define_singleton_method(:run) { |**_args| payload }
    end
    yield
  ensure
    originals.each { |klass, original| klass.define_singleton_method(:run, original) }
  end
end
