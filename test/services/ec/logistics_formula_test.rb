require "test_helper"

class Ec::LogisticsFormulaTest < ActiveSupport::TestCase
  Tariffs = Struct.new(:rows) do
    def for_volume(volume) = Struct.new(:rows, :volume) { def average(column) = rows.fetch(column.to_s, {}).find { |range, _| range.cover?(volume) }&.last }.new(rows, volume)
  end
  Snapshot = Struct.new(:logistics_tariffs)

  def with_tariff(rows)
    original = RawOzon::LogisticsTariffSnapshot.method(:current_for)
    snapshot = rows && Snapshot.new(Tariffs.new(rows))
    RawOzon::LogisticsTariffSnapshot.define_singleton_method(:current_for) { |**| snapshot }
    yield
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
      assert_equal({ mode: "formula", outbound_rub: 300.to_d, return_rub: 300.to_d, source: "ozon_route_average" }, info)

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
end
