require "test_helper"

class Ec::LogisticsFormulaTest < ActiveSupport::TestCase
  Tariffs = Struct.new(:rows) do
    def for_volume(volume) = Struct.new(:rows, :volume) { def average(column) = rows.fetch(column.to_s, {}).find { |range, _| range.cover?(volume) }&.last }.new(rows, volume)
  end
  Snapshot = Struct.new(:logistics_tariffs)

  def without_route_mix
    original = Ec::OzonRouteMix.method(:routes)
    Ec::OzonRouteMix.define_singleton_method(:routes) { |*| [] }
    yield
  ensure
    Ec::OzonRouteMix.define_singleton_method(:routes, original)
  end

  def with_tariff(rows)
    original = RawOzon::LogisticsTariffSnapshot.method(:current_for)
    snapshot = rows && Snapshot.new(Tariffs.new(rows))
    RawOzon::LogisticsTariffSnapshot.define_singleton_method(:current_for) { |**| snapshot }
    without_route_mix { yield }
  ensure
    RawOzon::LogisticsTariffSnapshot.define_singleton_method(:current_for, original)
  end

  INPUTS = { "length_cm" => 20, "width_cm" => 20, "height_cm" => 20, "commission_base_price_rub" => 2_000,
             "outbound_logistics_rub" => 111, "return_logistics_rub" => 55, "wb_logistics_override_cny" => 9 }.freeze
  ROWS = { "fbo_rub" => { (0..7) => 123.456, (7.001..30) => 300 }, "fbs_over_300_rub" => { (0..30) => 250 }, "fbs_under_300_rub" => { (0..30) => 90 } }.freeze

  test "the mode comes from the context, and a caller that does not say keeps the real figures" do
    assert_equal "formula", Ec::LogisticsFormula.mode_for("logistics_mode" => "formula")
    assert_equal "actual", Ec::LogisticsFormula.mode_for(logistics_mode: "actual")
    assert_equal "actual", Ec::LogisticsFormula.mode_for({})
    assert_equal "actual", Ec::LogisticsFormula.mode_for("logistics_mode" => "nonsense")
  end

  test "actual mode leaves the inputs alone" do
    inputs, info = Ec::LogisticsFormula.apply(platform: "wb", mode: "actual", parameter_context: {}, inputs: INPUTS)

    assert_equal 111, inputs["outbound_logistics_rub"]
    assert_equal({ mode: "actual", outbound_rub: nil, return_rub: nil, source: nil }, info)
  end

  test "WB on the formula drops the typed freight figures, so the base rate x coefficient and the flat return apply" do
    inputs, info = Ec::LogisticsFormula.apply(platform: "wb", mode: "formula", parameter_context: {}, inputs: INPUTS)

    assert_equal %w[commission_base_price_rub height_cm length_cm width_cm], inputs.keys.sort
    assert_equal "wb_coefficient", info[:source]
  end

  test "Ozon on the formula takes the route average of the SKU's volume for both legs; FBS picks its price column" do
    with_tariff(ROWS) do
      fbo, info = Ec::LogisticsFormula.apply(platform: "ozon", mode: "formula", parameter_context: { "delivery_mode" => "fbo" }, inputs: INPUTS)
      assert_equal [ 300.to_d, 300.to_d ], fbo.values_at("outbound_logistics_rub", "return_logistics_rub"), "8 litres falls in the second band"
      assert_equal({ mode: "formula", outbound_rub: 300.to_d, return_rub: 300.to_d, source: "ozon_route_average", route_basis: "all_routes" }, info.except(:route_count), "no routes for the scenario: every route of the tariff")

      small = INPUTS.merge("length_cm" => 10, "width_cm" => 10, "height_cm" => 5)
      assert_equal 123.46.to_d, Ec::LogisticsFormula.apply(platform: "ozon", mode: "formula", parameter_context: { "delivery_mode" => "fbo" }, inputs: small).first["outbound_logistics_rub"]

      over = Ec::LogisticsFormula.apply(platform: "ozon", mode: "formula", parameter_context: { "delivery_mode" => "fbs" }, inputs: INPUTS).first
      under = Ec::LogisticsFormula.apply(platform: "ozon", mode: "formula", parameter_context: { "delivery_mode" => "fbs" }, inputs: INPUTS.merge("commission_base_price_rub" => 250)).first
      assert_equal 250.to_d, over["outbound_logistics_rub"]
      assert_equal 90.to_d, under["outbound_logistics_rub"], "an item under 300 RUB pays the lower FBS price"
    end
  end

  test "Ozon on the formula without volume or tariff leaves the freight empty rather than guessing" do
    with_tariff(ROWS) do
      inputs, info = Ec::LogisticsFormula.apply(platform: "ozon", mode: "formula", parameter_context: { "delivery_mode" => "fbo" }, inputs: INPUTS.except("length_cm"))
      assert_nil inputs["outbound_logistics_rub"], "the typed figure is not used either"
      assert_nil info[:source]
    end
    with_tariff(nil) do
      assert_nil Ec::LogisticsFormula.apply(platform: "ozon", mode: "formula", parameter_context: { "delivery_mode" => "fbo" }, inputs: INPUTS).first["outbound_logistics_rub"]
    end
    with_tariff({ "fbo_rub" => { (100..200) => 5 } }) do
      assert_nil Ec::LogisticsFormula.apply(platform: "ozon", mode: "formula", parameter_context: { "delivery_mode" => "fbo" }, inputs: INPUTS).first["outbound_logistics_rub"], "no route covers 8 litres"
    end
  end

  test "Ozon averages the tariff of the scenario's busiest routes, equally weighted" do
    snapshot = RawOzon::LogisticsTariffSnapshot.create!(market_code: "zz#{SecureRandom.hex(3)}", effective_from: Date.new(2026, 1, 1), imported_at: Time.current,
      source_checksum: SecureRandom.hex(8), source_file_name: "test.xlsx", status: "succeeded")
    tariffs = [ [ "Москва", "Москва", 100 ], [ "Москва", "Казань", 200 ], [ "Москва", "Омск", 400 ] ]
    tariffs.each_with_index do |(origin, destination, fbo), index|
      RawOzon::LogisticsTariff.create!(snapshot: snapshot, origin_cluster_key: origin.downcase, origin_cluster_name: origin,
        destination_cluster_key: destination.downcase, destination_cluster_name: destination, volume_band_label: "0-30", volume_band_order: index,
        volume_min_l: 0, volume_max_l: 30, fbo_rub: fbo, fbo_fresh_under_300_rub: fbo, fbo_fresh_over_300_rub: fbo, fbs_over_300_rub: fbo, fbs_under_300_rub: fbo)
    end
    original = RawOzon::LogisticsTariffSnapshot.method(:current_for)
    RawOzon::LogisticsTariffSnapshot.define_singleton_method(:current_for) { |**| snapshot }
    one = BigDecimal("1")
    mix = [ [ "Москва", "Москва", one ], [ "Москва", "Казань", one ], [ "Москва", "Нигде", one ] ]
    original_routes = Ec::OzonRouteMix.method(:routes)
    Ec::OzonRouteMix.define_singleton_method(:routes) { |mode, market| mode == "fbo" && market == "ru" ? mix : [] }

    context = { "delivery_mode" => "fbo", "market" => "ru" }
    # (100 + 200) / 2: "Нигде" is not in the tariff, so it drops out and the others keep equal weights
    assert_equal 150.to_d, Ec::LogisticsFormula.ozon_route_average(INPUTS, context)
    basis = Ec::LogisticsFormula.ozon_route_basis(INPUTS, context)
    assert_equal({ average: 150.to_d, route_count: 2, basis: "top_routes" }, basis, "two of the three routes are in the tariff")
    info = Ec::LogisticsFormula.apply(platform: "ozon", mode: "formula", parameter_context: context, inputs: INPUTS).last
    assert_equal [ 2, "top_routes" ], info.values_at(:route_count, :route_basis)
    # a scenario without routes (Belarus FBO here) keeps the plain average of every route
    assert_equal (700.0 / 3).to_d.round(2), Ec::LogisticsFormula.ozon_route_average(INPUTS, context.merge("market" => "by"))
  ensure
    Ec::OzonRouteMix.define_singleton_method(:routes, original_routes) if original_routes
    RawOzon::LogisticsTariffSnapshot.define_singleton_method(:current_for, original) if original
    RawOzon::LogisticsTariff.where(snapshot_id: snapshot&.id).delete_all
    snapshot&.destroy
  end

  test "the route file picks the busiest routes: 40 for FBO, 20 for FBS, equal weights" do
    Ec::OzonRouteMix.reset!
    assert_equal 40, Ec::OzonRouteMix.top_routes("fbo")
    assert_equal 20, Ec::OzonRouteMix.top_routes("fbs")
    fbo = Ec::OzonRouteMix.routes("fbo", "ru")
    assert_equal 40, fbo.size
    assert_equal [ 1 ], fbo.map(&:last).uniq
    assert_equal [ "Москва, МО и Дальние регионы", "Москва, МО и Дальние регионы" ], fbo.first.first(2), "the busiest route comes first"
    assert_equal 20, Ec::OzonRouteMix.routes("fbs", "ru").size, "FBS ships on 20 routes in all"
    assert_equal 1, Ec::OzonRouteMix.routes("fbs", "by").size
    assert_empty Ec::OzonRouteMix.routes("fbo", "xx")
  end
end
