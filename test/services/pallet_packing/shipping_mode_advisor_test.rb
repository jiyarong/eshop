require "test_helper"

class PalletPacking::ShippingModeAdvisorTest < ActiveSupport::TestCase
  def quote(volume: 800, **overrides)
    tariff = RawOzon::CrossDockTariff.new(box_rub_per_l: 5, pallet_rub_per_l: 2.5)
    PalletPacking::ShippingModeAdvisor.new(**{ box_volumes_l: [volume / 20.0], box_quantities: [20],
      pallet_volumes_l: [volume], box_count: 20, tariff: tariff }.merge(overrides)).call
  end

  test "compares the same quantity using both rates and the pallet minimum" do
    small = quote
    assert_equal :box, small[:recommended]
    assert_equal :lowest_cost, small[:recommendation_reason]
    assert_equal 750, small[:savings]
    assert_equal BigDecimal("950"), small[:break_even_volume_l]
    assert_equal 4000, small[:box][:cost]
    assert_equal 4750, small[:pallet][:cost]
    assert_equal :pallet, quote(volume: 2500)[:recommended]
    assert_equal 6250, quote(volume: 2500)[:savings]
  end

  test "point types and named exceptions precede price" do
    assert_equal :box, quote(volume: 2500, point_type: "pvz")[:recommended]
    assert_equal 12_500, quote(volume: 2500, point_type: "pvz")[:box][:handling]
    assert_equal :point_type, quote(point_name: "Софьино")[:blocked_by]
    assert_equal :pallet, quote(point_name: "Софьино")[:recommended]
    assert_equal :box, quote(volume: 2500, point_name: "СЦ Ханты-Мансийск")[:recommended]
  end

  test "box limits and each pallet minimum are enforced" do
    assert_equal :pallet, quote(box_count: 31)[:recommended]
    assert_equal :box_count_limit, quote(box_count: 31)[:box][:blocked_by]
    assert_equal 9500, quote(pallet_volumes_l: [400, 400])[:pallet][:cost]
    assert_not quote(pallet_volumes_l: Array.new(41, 20))[:pallet][:available]
  end

  test "missing quotes and volumes remain unknown" do
    missing = quote(tariff: nil)
    assert_nil missing[:recommended]
    assert_nil missing[:recommendation_reason]
    assert_nil missing[:savings]
    assert_nil missing[:box][:cost]
    assert_nil missing[:pallet][:rate]
    assert_equal [:route_rate], missing[:box][:missing]
    assert_nil quote(box_volumes_l: [nil])[:box][:cost]
  end

  test "a sole feasible mode is recommended without inventing a quote" do
    box = quote(tariff: nil, point_type: "pvz")
    assert_equal :box, box[:recommended]
    assert_equal :only_available, box[:recommendation_reason]
    assert_nil box[:box][:cost]
    assert_nil box[:savings]
    assert_equal :point_type, box[:pallet][:blocked_by]

    pallet = quote(tariff: nil, box_count: 31)
    assert_equal :pallet, pallet[:recommended]
    assert_equal :only_available, pallet[:recommendation_reason]
    assert_nil pallet[:pallet][:cost]
    assert_nil pallet[:savings]
  end

  test "neither infeasible modes nor a partial quote produce a cost recommendation" do
    none = quote(box_allowed: false, pallet_allowed: false)
    assert_nil none[:recommended]
    assert_nil none[:recommendation_reason]
    assert_nil none[:savings]

    partial = quote(tariff: RawOzon::CrossDockTariff.new(box_rub_per_l: 5))
    assert_equal 4000, partial[:box][:cost]
    assert_nil partial[:pallet][:cost]
    assert_nil partial[:recommended]
    assert_nil partial[:savings]
  end
end
