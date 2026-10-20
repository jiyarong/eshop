require "test_helper"

class Ec::SkuProfitPriceFromActualsTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "PFA-#{@token}", product_name: "Price fill")
    @version_ids = []
  end

  teardown do
    context_ids = Ec::SkuProfitVersionContext.where(sku_profit_version_id: @version_ids).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersionContext", record_id: context_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: @version_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::SkuProfitVersionContext.where(id: context_ids).delete_all
    Ec::SkuProfitVersion.where(id: @version_ids).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "fills only empty prices of draft versions from the scenario's own realized price and recalculates" do
    version = create_version("draft", [
      scenario("wb", "ru", "fbo", "small", price: nil),
      scenario("wb", "ru", "fbs", "small", price: nil),
      scenario("wb", "ru", "fbo", "general", price: 999)
    ])

    summary = with_prices({ %w[wb ru fbo small] => 1_100, %w[wb ru fbs small] => nil, %w[wb ru fbo general] => 5_555 }) do
      run_fill(version)
    end

    assert summary.fetch(:ok), summary.inspect
    assert_equal 1, summary.fetch(:filled).size
    assert_equal "no_orders_in_scenario", summary.fetch(:not_filled).sole.fetch(:reason)
    version.reload
    filled = version.context_for(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small")
    empty = version.context_for(platform: "wb", market: "ru", delivery_mode: "fbs", warehouse_region: "main", company_type: "small")
    priced = version.context_for(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general")
    assert_equal 1_100.to_d, filled.commission_base_price_rub
    assert_equal "valid", filled.calculation_status
    assert_nil empty.commission_base_price_rub
    assert_equal "incomplete", empty.calculation_status
    assert_equal 999.to_d, priced.commission_base_price_rub, "an existing price is never overwritten"
  end

  test "a dry run and a published version change nothing, and too few units are not enough" do
    draft = create_version("draft", [ scenario("wb", "ru", "fbo", "small", price: nil) ])
    published = create_version("published", [ scenario("wb", "ru", "fbo", "small", price: nil) ], effective_from: Date.new(2026, 1, 1))

    dry = with_prices({ %w[wb ru fbo small] => 1_100 }) { run_fill(draft, dry_run: true) }
    assert_equal 1, dry.fetch(:filled).size
    assert_nil draft.reload.contexts.sole.commission_base_price_rub

    scoped = with_prices({ %w[wb ru fbo small] => 1_100 }) do
      Ec::SkuProfitPriceFromActuals.run(scope: Ec::SkuProfitVersion.where(id: published.id, status: "draft"), dry_run: false)
    end
    assert_equal 0, scoped.fetch(:versions)

    few = with_prices({ %w[wb ru fbo small] => 1_100 }, units: 4) { run_fill(draft) }
    assert_equal "too_few_units", few.fetch(:not_filled).sole.fetch(:reason)
    assert_equal 5, Ec::SkuProfitPriceFromActuals::MIN_UNITS

    enough = with_prices({ %w[wb ru fbo small] => 1_100 }, units: 5) { run_fill(draft, dry_run: true) }
    assert_equal 1, enough.fetch(:filled).size
  end

  private

  def run_fill(version, dry_run: false)
    Ec::SkuProfitPriceFromActuals.run(scope: Ec::SkuProfitVersion.where(id: version.id), dry_run:, today: Date.new(2026, 9, 14))
  end

  def scenario(platform, market, delivery_mode, company_type, price:)
    inputs = Ec::SkuProfitCalculator.default_inputs(
      platform:, parameter_context: { "market" => market, "delivery_mode" => delivery_mode, "company_type" => company_type }
    ).merge(
      "purchase_price_cny" => 77, "freight_cny" => 10, "customs_misc_cny" => 2, "duty_rate" => 0.1, "import_vat_rate" => 0.2,
      "length_cm" => 10, "width_cm" => 10, "height_cm" => 10, "commission_rate" => 0.185,
      "outbound_logistics_rub" => 100, "return_logistics_rub" => 50, "commission_base_price_rub" => price
    )
    { identity: { platform:, market:, delivery_mode:, warehouse_region: "main", company_type: }, inputs: inputs }
  end

  def create_version(status, scenarios, effective_from: Date.new(2026, 9, 1))
    version = @sku.profit_versions.new(name: "fill #{@token}", status:, effective_from:,
      note: "#{Ec::SkuProfitPriceFromActuals::IMPORT_NOTE_PREFIX}v1:test")
    scenarios.each do |entry|
      context = version.contexts.build(entry.fetch(:identity))
      context.assign_input_values(entry.fetch(:inputs))
    end
    Ec::SkuProfitVersionRecalculator.call(version)
    version.save!
    @version_ids << version.id
    version
  end

  # Canned realized prices per [platform, market, delivery_mode, company_type]; nil = no orders.
  def with_prices(prices, units: 10)
    original = Ec::SkuActualScenarioPriceQuery.method(:run)
    Ec::SkuActualScenarioPriceQuery.define_singleton_method(:run) do |**args|
      average = prices[[ args[:platform], args[:market], args[:delivery_mode], args[:company_type] ]]
      { commission_base_price: { average_rub: average && BigDecimal(average.to_s), unit_count: average ? units : 0,
        item_count: average ? 3 : 0, missing_exchange_rate_item_count: 0 } }
    end
    yield
  ensure
    Ec::SkuActualScenarioPriceQuery.define_singleton_method(:run, original)
  end
end
