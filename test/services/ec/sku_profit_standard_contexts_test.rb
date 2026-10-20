require "test_helper"

class Ec::SkuProfitStandardContextsTest < ActiveSupport::TestCase
  SCENARIOS = Ec::SkuProfitStandardContexts::SCENARIOS

  test "there are twelve distinct scenarios: platform x market x tax regime x fulfilment" do
    assert_equal 12, SCENARIOS.size
    assert_equal 12, SCENARIOS.map { |scenario| Ec::SkuProfitStandardContexts.key_for(scenario) }.uniq.size

    wb = SCENARIOS.select { |scenario| scenario["platform"] == "wb" }
    assert_equal 8, wb.size
    assert_equal %w[by ru], wb.map { |scenario| scenario["market"] }.uniq.sort
    assert_equal %w[general small], wb.map { |scenario| scenario["company_type"] }.uniq.sort

    ozon = SCENARIOS.select { |scenario| scenario["platform"] == "ozon" }
    assert_equal 4, ozon.size
    assert_equal [ "general" ], ozon.map { |scenario| scenario["company_type"] }.uniq
    assert_equal %w[fbo fbs], ozon.map { |scenario| scenario["delivery_mode"] }.uniq.sort
  end

  test "every scenario is main-warehouse, lower case and frozen" do
    SCENARIOS.each do |scenario|
      assert_equal "main", scenario["warehouse_region"]
      assert scenario.values.all? { |value| value == value.downcase }
      assert scenario.frozen?
    end
  end

  test "every scenario calculates once its prices are filled in" do
    SCENARIOS.each do |scenario|
      parameter_context = scenario.slice("market", "delivery_mode", "warehouse_region", "company_type")
      inputs = Ec::SkuProfitCalculator.default_inputs(platform: scenario["platform"], parameter_context: parameter_context).merge(
        "purchase_price_cny" => "100", "length_cm" => "20", "width_cm" => "20", "height_cm" => "10",
        "commission_base_price_rub" => "3000", "commission_rate" => "0.2",
        "outbound_logistics_rub" => "150", "return_logistics_rub" => "100"
      )
      result = Ec::ProfitCalculator.call(platform: scenario["platform"], parameter_context: parameter_context, inputs: inputs)

      assert_empty result[:errors].to_a, Ec::SkuProfitStandardContexts.key_for(scenario)
      assert result[:profit_cny].is_a?(Numeric), Ec::SkuProfitStandardContexts.key_for(scenario)
    end
  end

  test "only the scenarios whose actual-data queries are not split yet are flagged" do
    pending = SCENARIOS.reject { |scenario| Ec::SkuProfitStandardContexts.actuals_split?(scenario) }

    assert_equal 6, pending.size
    assert pending.all? { |scenario| scenario["market"] == "by" && scenario["platform"] == "wb" || scenario["platform"] == "ozon" && scenario["delivery_mode"] == "fbs" }
    assert Ec::SkuProfitStandardContexts.actuals_split?("platform" => "wb", "market" => "ru", "delivery_mode" => "fbo", "company_type" => "general")
  end

  test "sorting follows the configured order and puts unknown identities last" do
    version = Ec::SkuProfitVersion.new
    SCENARIOS.reverse_each { |scenario| version.contexts.build(scenario) }
    extra = version.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "regional", company_type: "general")

    ordered = Ec::SkuProfitStandardContexts.sort(version.contexts)

    assert_equal SCENARIOS.map { |scenario| Ec::SkuProfitStandardContexts.key_for(scenario) },
      ordered.first(12).map { |context| Ec::SkuProfitStandardContexts.key_for(context.attributes.slice(*Ec::SkuProfitStandardContexts::IDENTITY_KEYS)) }
    assert_equal extra, ordered.last
  end

  test "the missing scenarios of an old six-scenario version are built with their market defaults" do
    sku = Ec::Sku.new(sku_code: "SC-#{SecureRandom.hex(3)}")
    version = Ec::SkuProfitVersion.new(sku: sku, name: "old", effective_from: Date.new(2026, 10, 1))
    SCENARIOS.first(2).each { |scenario| version.contexts.build(scenario) }

    built = Ec::SkuProfitStandardContexts.build_missing(version, sku: sku, effective_on: Date.new(2026, 10, 1))

    assert_equal 10, built.size
    belarus = built.find { |context| context.platform == "wb" && context.market == "by" && context.delivery_mode == "fbs" && context.company_type == "small" }
    assert_equal 0.019.to_d, belarus.acquiring_rate
    assert_equal 0.1.to_d, belarus.return_rate
    fbs = built.find { |context| context.platform == "ozon" && context.delivery_mode == "fbs" && context.market == "ru" }
    assert_equal 30.to_d, fbs.fbs_handover_rub
    assert_nil fbs.warehouse_operation_rub
  end

  test "a scenario added with price prefill takes the price the SKU really sold it for, and stays empty where nothing sold" do
    sku = Ec::Sku.new(sku_code: "PF-#{SecureRandom.hex(3)}")
    version = Ec::SkuProfitVersion.new(sku: sku, name: "old", effective_from: Date.new(2026, 10, 1))
    SCENARIOS.first(2).each { |scenario| version.contexts.build(scenario) }
    asked = []
    original = Ec::SkuProfitPriceFromActuals.method(:realized_price_for)
    Ec::SkuProfitPriceFromActuals.define_singleton_method(:realized_price_for) do |_sku, context, **options|
      asked << [ context.platform, context.market, context.delivery_mode, context.company_type, options[:weeks] ]
      context.platform == "ozon" && context.delivery_mode == "fbs" ? { price_rub: BigDecimal("2750.5"), units: 9, orders: 4 } : { reason: "too_few_units", units: 2 }
    end

    built = Ec::SkuProfitStandardContexts.build_missing(version, sku: sku, effective_on: Date.new(2026, 10, 1),
      prefill_prices: { today: Date.new(2026, 10, 20), time_zone: ActiveSupport::TimeZone["Asia/Shanghai"] })

    assert_equal 10, asked.size, "only the scenarios the version lacked were priced"
    assert asked.all? { |entry| entry.last == 12 }, "over the last twelve weeks"
    prices = built.to_h { |context| [ [ context.platform, context.market, context.delivery_mode ], context.commission_base_price_rub ] }
    assert_equal 2750.5.to_d, prices.fetch([ "ozon", "ru", "fbs" ])
    assert_equal 2750.5.to_d, prices.fetch([ "ozon", "by", "fbs" ])
    assert_nil prices.fetch([ "wb", "by", "fbo" ])
    assert_nil prices.fetch([ "ozon", "ru", "fbo" ])
  ensure
    Ec::SkuProfitPriceFromActuals.define_singleton_method(:realized_price_for, original) if original
  end

  test "without prefill no price is looked up, and a failing lookup leaves the price empty instead of failing the page" do
    sku = Ec::Sku.new(sku_code: "PF-#{SecureRandom.hex(3)}")
    version = Ec::SkuProfitVersion.new(sku: sku, name: "old", effective_from: Date.new(2026, 10, 1))
    original = Ec::SkuProfitPriceFromActuals.method(:realized_price_for)
    calls = 0
    Ec::SkuProfitPriceFromActuals.define_singleton_method(:realized_price_for) { |*_args, **_options| calls += 1; raise "boom" }

    Ec::SkuProfitStandardContexts.build_missing(version, sku: sku, effective_on: Date.new(2026, 10, 1))
    assert_equal 0, calls

    built = Ec::SkuProfitStandardContexts.build_missing(Ec::SkuProfitVersion.new(sku: sku, name: "x", effective_from: Date.new(2026, 10, 1)), sku: sku,
      effective_on: Date.new(2026, 10, 1), prefill_prices: { today: Date.new(2026, 10, 20), time_zone: ActiveSupport::TimeZone["Asia/Shanghai"] })
    assert_equal 12, built.size
    assert built.all? { |context| context.commission_base_price_rub.nil? }
  ensure
    Ec::SkuProfitPriceFromActuals.define_singleton_method(:realized_price_for, original) if original
  end
end
