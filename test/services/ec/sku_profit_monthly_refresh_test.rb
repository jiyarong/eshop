require "test_helper"

class Ec::SkuProfitMonthlyRefreshTest < ActiveSupport::TestCase
  MONTH_START = Date.new(2026, 11, 1)

  setup do
    @token = SecureRandom.hex(5).upcase
    @skus = []
  end

  teardown do
    sku_ids = @skus.map(&:id)
    version_ids = Ec::SkuProfitVersion.where(sku_id: sku_ids).pluck(:id)
    context_ids = Ec::SkuProfitVersionContext.where(sku_profit_version_id: version_ids).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersionContext", record_id: context_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: version_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: sku_ids).delete_all
    Ec::SkuProfitVersionContext.where(id: context_ids).delete_all
    Ec::SkuProfitVersion.where(id: version_ids).delete_all
    Ec::Sku.unscoped.where(id: sku_ids).delete_all
  end

  test "copies the latest version into a draft for the month and refreshes only the actual-data inputs" do
    sku = create_sku("MR-#{@token}")
    create_version(sku, "published", Date.new(2026, 9, 1), price: 1_000, return_rate: 0.3, effective_to: Date.new(2026, 9, 30))
    previous = create_version(sku, "published", Date.new(2026, 10, 1), price: 12_500, return_rate: 0.1)

    summary = nil
    with_actuals(logistics: { outbound: { average_rub: BigDecimal("210.5") }, return: { average_rub: BigDecimal("48") } },
      return_rate: { return_rate: { rate: BigDecimal("0.12") } }) do
      summary = run_refresh
    end

    assert summary.fetch(:ok), summary.inspect
    version = sku.profit_versions.find_by!(effective_from: MONTH_START)
    assert_equal "draft", version.status
    assert_equal "月度自动更新 2026-11", version.name
    assert_equal 6, version.contexts.count
    assert_equal [ previous.id ], summary.fetch(:created).map { |entry| entry.fetch(:copied_from_version_id) }

    wb = version.context_for(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small")
    # Carried over from the previous version.
    assert_equal 12_500.to_d, wb.commission_base_price_rub
    assert_equal 77.to_d, wb.purchase_price_cny
    assert_equal 0.185.to_d, wb.commission_rate
    # Refreshed from the last four weeks.
    assert_equal 210.5.to_d, wb.outbound_logistics_rub
    assert_equal 48.to_d, wb.return_logistics_rub
    assert_equal 0.12.to_d, wb.return_rate
    # The copy is a fresh calculation, not the previous version's stored result.
    assert_equal "valid", wb.calculation_status
    assert_not_nil wb.profit_cny
    # The previous version is untouched.
    assert_equal 0.1.to_d, previous.reload.contexts.find_by(platform: "wb", delivery_mode: "fbo", company_type: "small").return_rate
  end

  test "a scenario without a price gets its own realized price when enough units sold, existing prices stay" do
    sku = create_sku("MP-#{@token}")
    version = sku.profit_versions.new(name: "v", status: "published", effective_from: Date.new(2026, 10, 1))
    [ [ "fbo", 12_500 ], [ "fbs", nil ] ].each do |mode, price|
      identity = { "platform" => "wb", "market" => "ru", "delivery_mode" => mode, "warehouse_region" => "main", "company_type" => "small" }
      context = version.contexts.build(identity)
      context.assign_input_values(
        Ec::SkuProfitCalculator.default_inputs(platform: "wb", parameter_context: identity).merge(
          "purchase_price_cny" => 77, "freight_cny" => 10, "customs_misc_cny" => 2, "duty_rate" => 0.1,
          "import_vat_rate" => 0.2, "length_cm" => 10, "width_cm" => 10, "height_cm" => 10, "commission_rate" => 0.185,
          "commission_base_price_rub" => price
        )
      )
    end
    version.save!

    prices = { [ "wb", "ru", "fbo", "small" ] => [ 9_999, 50 ], [ "wb", "ru", "fbs", "small" ] => [ 3_100, 7 ],
               [ "wb", "ru", "fbo", "general" ] => [ 2_000, 4 ] }
    original = Ec::SkuActualScenarioPriceQuery.method(:run)
    Ec::SkuActualScenarioPriceQuery.define_singleton_method(:run) do |**args|
      average, units = prices.fetch([ args[:platform], args[:market], args[:delivery_mode], args[:company_type] ], [ nil, 0 ])
      { commission_base_price: { average_rub: average && BigDecimal(average.to_s), unit_count: units, item_count: 2, missing_exchange_rate_item_count: 0 } }
    end
    begin
      summary = run_refresh
    ensure
      Ec::SkuActualScenarioPriceQuery.define_singleton_method(:run, original)
    end

    created = sku.profit_versions.find_by!(effective_from: MONTH_START)
    price_of = lambda do |mode, company|
      created.context_for(platform: "wb", market: "ru", delivery_mode: mode, warehouse_region: "main", company_type: company)&.commission_base_price_rub
    end
    assert_equal 12_500.to_d, price_of.call("fbo", "small"), "an existing price is never replaced"
    assert_equal 3_100.to_d, price_of.call("fbs", "small")
    assert_nil price_of.call("fbo", "general"), "4 units are below the 5-unit minimum"
    assert_equal 1, summary.fetch(:created).sole.fetch(:prices_filled)
  end

  test "a figure without platform data keeps the previous version's value" do
    sku = create_sku("MK-#{@token}")
    create_version(sku, "published", Date.new(2026, 10, 1), price: 9_000, return_rate: 0.22)

    run_refresh

    wb = sku.profit_versions.find_by!(effective_from: MONTH_START)
      .context_for(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small")
    assert_equal 0.22.to_d, wb.return_rate
  end

  test "running again in the month, or with a version already on the 1st, creates nothing" do
    sku = create_sku("MI-#{@token}")
    other = create_sku("MJ-#{@token}")
    create_version(sku, "published", Date.new(2026, 10, 1), price: 9_000, return_rate: 0.1)
    create_version(other, "published", Date.new(2026, 10, 1), price: 9_000, return_rate: 0.1)
    create_version(other, "draft", MONTH_START, price: 9_500, return_rate: 0.1)

    first = run_refresh
    second = run_refresh

    assert_equal [ sku.sku_code ], first.fetch(:created).map { |entry| entry.fetch(:sku_code) }
    assert_equal [ other.sku_code ], first.fetch(:skipped_existing)
    assert_empty second.fetch(:created)
    assert_equal [ sku.sku_code, other.sku_code ].sort, second.fetch(:skipped_existing).sort
    assert_equal 2, sku.profit_versions.count
  end

  test "SKUs without any version are left alone, and a dry run writes nothing" do
    bare = create_sku("MB-#{@token}")
    dry = create_sku("MD-#{@token}")
    create_version(dry, "published", Date.new(2026, 10, 1), price: 9_000, return_rate: 0.1)

    assert_no_difference -> { Ec::SkuProfitVersion.count } do
      summary = run_refresh(dry_run: true)
      assert_equal [ dry.sku_code ], summary.fetch(:created).map { |entry| entry.fetch(:sku_code) }
    end
    assert_empty bare.profit_versions
  end

  test "the first day of the month is derived from today and the job is scheduled for it" do
    refresh = Ec::SkuProfitMonthlyRefresh.new(today: Date.new(2026, 12, 17))
    assert_equal "2026-12-01", refresh.call.fetch(:month_start)

    recurring = YAML.safe_load_file(Rails.root.join("config/recurring.yml")).fetch("production")
    assert_equal "Ec::SkuProfitMonthlyRefresh.run", recurring.dig("sku_profit_monthly_refresh", "command")
    assert_equal "every month on the 1st at 7:00 in Asia/Shanghai", recurring.dig("sku_profit_monthly_refresh", "schedule")
  end

  private

  def run_refresh(dry_run: false)
    Ec::SkuProfitMonthlyRefresh.run(
      month_start: MONTH_START, today: MONTH_START, dry_run:, sku_scope: Ec::Sku.where(id: @skus.map(&:id))
    )
  end

  def create_sku(code)
    sku = Ec::Sku.create!(sku_code: code, product_name: "Monthly refresh test", is_active: true)
    @skus << sku
    sku
  end

  def create_version(sku, status, effective_from, price:, return_rate:, effective_to: nil)
    version = sku.profit_versions.new(name: "v #{effective_from}", status:, effective_from:, effective_to:)
    Ec::SkuProfitStandardContexts::SCENARIOS.each do |identity|
      context = version.contexts.build(identity)
      context.assign_input_values(
        Ec::SkuProfitCalculator.default_inputs(platform: identity.fetch("platform"), parameter_context: identity).merge(
          "purchase_price_cny" => 77, "freight_cny" => 10, "customs_misc_cny" => 2, "duty_rate" => 0.1,
          "import_vat_rate" => 0.2, "length_cm" => 10, "width_cm" => 10, "height_cm" => 10,
          "commission_base_price_rub" => price, "commission_rate" => 0.185, "return_rate" => return_rate,
          "outbound_logistics_rub" => 100, "return_logistics_rub" => 50, "warehouse_operation_rub" => 25
        )
      )
    end
    version.save!
    version
  end

  # Canned payloads for the actual-data queries; nil keeps the real (empty-DB) answer.
  def with_actuals(logistics: nil, return_rate: nil)
    stubs = { Ec::SkuActualLogisticsQuery => logistics, Ec::SkuActualReturnRateQuery => return_rate }.select { |_klass, payload| payload }
    originals = stubs.keys.index_with { |klass| klass.method(:run) }
    stubs.each { |klass, payload| klass.define_singleton_method(:run) { |**_args| payload } }
    yield
  ensure
    originals.each { |klass, original| klass.define_singleton_method(:run, original) }
  end
end
