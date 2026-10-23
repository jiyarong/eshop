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
    cost_ids = Ec::SkuCost.where(sku_code: @skus.map(&:sku_code)).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersionContext", record_id: context_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: version_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuCost", record_id: cost_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: sku_ids).delete_all
    Ec::SkuProfitVersionContext.where(id: context_ids).delete_all
    Ec::SkuProfitVersion.where(id: version_ids).delete_all
    Ec::SkuCost.where(id: cost_ids).delete_all
    Ec::Sku.unscoped.where(id: sku_ids).delete_all
  end

  test "builds an automatic version for the month with every standard scenario and its data window" do
    sku = create_sku("MR-#{@token}")

    summary = run_refresh

    assert summary.fetch(:ok), summary.inspect
    # 2026-11-01 is a Sunday: the four full weeks before the Monday of its week, 2026-10-26.
    assert_equal "2026-09-28", summary.fetch(:data_from)
    assert_equal "2026-10-25", summary.fetch(:data_to)
    version = sku.profit_versions.automatic.sole
    assert version.automatic?
    assert_equal "published", version.status
    assert_not version.is_current?
    assert_equal "2026-11", version.name
    assert_equal MONTH_START, version.effective_from
    assert_equal Date.new(2026, 11, 30), version.effective_to
    assert_equal Date.new(2026, 9, 28), version.data_from
    assert_equal Date.new(2026, 10, 25), version.data_to
    assert_equal Ec::SkuProfitStandardContexts::SCENARIOS.size, version.contexts.count
    assert_equal Ec::SkuProfitStandardContexts::SCENARIOS.size, summary.fetch(:built).sole.fetch(:scenarios)
  end

  test "fills the inputs from the SKU file and the platform data, takes nothing from earlier versions" do
    sku = create_sku("MS-#{@token}")
    create_cost(sku)
    # A manual version of the SKU with its own figures: nothing of it may reach the automatic one.
    manual = sku.profit_versions.new(name: "mine", status: "draft", effective_from: Date.new(2026, 10, 1))
    manual.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small",
      commission_base_price_rub: 99_999, commission_rate: 0.5, return_rate: 0.9)
    manual.save!

    with_actuals(logistics: { outbound: { average_rub: BigDecimal("210.5") }, return: { average_rub: BigDecimal("48") }, handover: { average_rub: BigDecimal("33") } },
      return_rate: { return_rate: { rate: BigDecimal("0.12") } },
      storage: { storage: { average_rub: BigDecimal("130") } }, advertising: { rate: BigDecimal("0.05") }) do
      run_refresh
    end

    version = sku.profit_versions.automatic.sole
    wb = version.context_for(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small")
    assert_equal 77.to_d, wb.purchase_price_cny, "from the SKU file"
    assert_equal 0.12.to_d, wb.return_rate, "from the platform data, not the manual 0.9"
    assert_equal 210.5.to_d, wb.outbound_logistics_rub
    assert_equal 48.to_d, wb.return_logistics_rub
    assert_equal 10.to_d, wb.storage_cny
    assert_equal 0.05.to_d, wb.advertising_rate
    assert_nil wb.commission_base_price_rub, "no sold units, no price: it is not carried over from the manual version"
    assert_nil wb.commission_rate, "no official rate, no rate: it is not carried over from the manual version"
    assert_equal "incomplete", wb.calculation_status
    assert_nil wb.profit_cny

    ozon_fbs = version.context_for(platform: "ozon", market: "ru", delivery_mode: "fbs", warehouse_region: "main", company_type: "general")
    assert_equal 33.to_d, ozon_fbs.fbs_handover_rub
    assert_equal 0.05.to_d, ozon_fbs.advertising_rate
  end

  test "a scenario with a price, a rate and real freight is calculated on the real freight" do
    sku = create_sku("MA-#{@token}")
    create_cost(sku)

    with_price(9_999, 50) do
      with_commission(BigDecimal("0.185")) do
        with_actuals(logistics: { outbound: { average_rub: BigDecimal("210.5") }, return: { average_rub: BigDecimal("48") } },
          return_rate: { return_rate: { rate: BigDecimal("0.12") } }) do
          run_refresh
        end
      end
    end

    wb = sku.profit_versions.automatic.sole.context_for(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small")
    assert_equal 9_999.to_d, wb.commission_base_price_rub
    assert_equal 0.185.to_d, wb.commission_rate
    assert_equal "valid", wb.calculation_status
    assert_not_nil wb.profit_cny
    assert_equal "actual", wb.logistics_mode
    assert_equal 210.5.to_d, wb.outbound_logistics_rub
  end

  test "a scenario without real freight is calculated on the fixed formula and holds no freight figures" do
    sku = create_sku("MF-#{@token}")
    create_cost(sku)

    with_price(9_999, 50) do
      with_commission(BigDecimal("0.185")) do
        with_actuals(logistics: { outbound: { average_rub: nil }, return: { average_rub: BigDecimal("48") } }) { run_refresh }
      end
    end

    wb = sku.profit_versions.automatic.sole.context_for(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small")
    assert_equal "formula", wb.logistics_mode
    assert_nil wb.outbound_logistics_rub
    assert_nil wb.return_logistics_rub
    assert_equal "valid", wb.calculation_status
  end

  test "one sold unit is enough for a price, a scenario nobody bought from has none" do
    sold = create_sku("MP-#{@token}")
    unsold = create_sku("MU-#{@token}")

    with_price(9_999, 1) { Ec::SkuProfitMonthlyRefresh.run(month_start: MONTH_START, today: MONTH_START, sku_scope: Ec::Sku.where(id: sold.id)) }
    with_price(nil, 0) { Ec::SkuProfitMonthlyRefresh.run(month_start: MONTH_START, today: MONTH_START, sku_scope: Ec::Sku.where(id: unsold.id)) }

    identity = { platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small" }
    assert_equal 9_999.to_d, sold.profit_versions.automatic.sole.context_for(**identity).commission_base_price_rub
    assert_nil unsold.profit_versions.automatic.sole.context_for(**identity).commission_base_price_rub
  end

  test "rebuilding the same month replaces the version, other months and manual versions stay" do
    sku = create_sku("MI-#{@token}")
    manual = sku.profit_versions.create!(name: "mine", status: "draft", effective_from: MONTH_START)
    october = nil
    Ec::SkuProfitMonthlyRefresh.run(month_start: Date.new(2026, 10, 1), today: Date.new(2026, 10, 1), sku_scope: Ec::Sku.where(id: sku.id))
    october = sku.profit_versions.automatic.find_by!(effective_from: Date.new(2026, 10, 1))

    first = run_refresh
    first_id = sku.profit_versions.automatic.find_by!(effective_from: MONTH_START).id
    second = run_refresh

    assert first.fetch(:ok) && second.fetch(:ok)
    november = sku.profit_versions.automatic.find_by!(effective_from: MONTH_START)
    assert_not_equal first_id, november.id, "the month's version is rebuilt"
    assert_equal 2, sku.profit_versions.automatic.count
    assert Ec::SkuProfitVersion.exists?(october.id)
    assert Ec::SkuProfitVersion.exists?(manual.id)
    assert manual.reload.manual?
    assert_equal 0, Ec::SkuProfitVersionContext.where(sku_profit_version_id: first_id).count, "the replaced version's scenarios go with it"
  end

  test "every active SKU gets a version, inactive ones do not, and a dry run writes nothing" do
    active = create_sku("MB-#{@token}")
    inactive = create_sku("MD-#{@token}")
    inactive.update_columns(is_active: false)
    scope = Ec::Sku.where(id: [ active.id, inactive.id ], is_active: true)

    assert_no_difference -> { Ec::SkuProfitVersion.count } do
      summary = Ec::SkuProfitMonthlyRefresh.run(month_start: MONTH_START, today: MONTH_START, dry_run: true, sku_scope: scope)
      assert_equal [ active.sku_code ], summary.fetch(:built).map { |entry| entry.fetch(:sku_code) }
    end

    Ec::SkuProfitMonthlyRefresh.run(month_start: MONTH_START, today: MONTH_START, sku_scope: scope)
    assert_equal 1, active.profit_versions.automatic.count
    assert_empty inactive.profit_versions
  end

  test "the summary says which scenarios cannot be calculated and why" do
    sku = create_sku("MN-#{@token}")

    entry = run_refresh.fetch(:built).sole

    assert_equal entry.fetch(:scenarios), entry.fetch(:not_calculable).size
    wb = entry.fetch(:not_calculable).find { |scenario| scenario.fetch(:scenario) == "wb|ru|fbo|main|small" }
    assert_equal "no_listings", wb.dig(:reasons, "commission_rate")
    assert_equal "no_orders_in_scenario", wb.dig(:reasons, "price")
    assert_includes wb.fetch(:errors), "missing_commission_base_price_rub"
    assert_equal sku.sku_code, entry.fetch(:sku_code)
  end

  test "the first day of the month is derived from today and the job is scheduled for it" do
    refresh = Ec::SkuProfitMonthlyRefresh.new(today: Date.new(2026, 12, 17), sku_scope: Ec::Sku.none)
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

  def create_cost(sku)
    Ec::SkuCost.create!(
      sku_code: sku.sku_code, effective_on: Date.new(2026, 1, 1), purchase_price_cny: 77, freight_to_by_cny: 10,
      customs_misc_cny: 2, customs_duty_rate: 0.1, import_vat_rate: 0.2, pkg_length_cm: 10, pkg_width_cm: 10, pkg_height_cm: 10
    )
  end

  # Canned payloads for the actual-data queries; nil keeps the real (empty-DB) answer.
  def with_actuals(logistics: nil, return_rate: nil, storage: nil, advertising: nil)
    stubs = {
      Ec::SkuActualLogisticsQuery => logistics, Ec::SkuActualReturnRateQuery => return_rate,
      Ec::SkuActualStorageQuery => storage, Ec::SkuActualAdvertisingQuery => advertising
    }.select { |_klass, payload| payload }
    originals = stubs.keys.index_with { |klass| klass.method(:run) }
    stubs.each { |klass, payload| klass.define_singleton_method(:run) { |**_args| payload } }
    yield
  ensure
    originals.each { |klass, original| klass.define_singleton_method(:run, original) }
  end

  # Every scenario sold `units` units at `average` RUB (nil: nothing sold).
  def with_price(average, units)
    original = Ec::SkuActualScenarioPriceQuery.method(:run)
    Ec::SkuActualScenarioPriceQuery.define_singleton_method(:run) do |**_args|
      { commission_base_price: { average_rub: average && BigDecimal(average.to_s), unit_count: units, item_count: 2, missing_exchange_rate_item_count: 0 } }
    end
    yield
  ensure
    Ec::SkuActualScenarioPriceQuery.define_singleton_method(:run, original)
  end

  def with_commission(rate)
    original = Ec::SkuOfficialCommissionRate.method(:call)
    Ec::SkuOfficialCommissionRate.define_singleton_method(:call) { |**_args| { rate: rate, reason: nil } }
    yield
  ensure
    Ec::SkuOfficialCommissionRate.define_singleton_method(:call, original)
  end
end
