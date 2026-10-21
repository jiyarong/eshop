require "test_helper"

class Ec::PalletPlans::BoxPackingTest < ActiveSupport::TestCase
  def item(**overrides)
    { sku_code: "BOX", length: 40, width: 30, height: 20, weight: 25, pcs: 2,
      unit_volume_l: 0.2, quantity: 2, ozon_size_category: "normal" }.merge(overrides)
  end

  test "rounds each carton separately without a pallet minimum and conserves units" do
    result = Ec::PalletPlans::BoxPacking.new(items: [item], settings: { route_rate: 5, fixed_fee: 10 }).call
    assert_equal "box", result[:shipping_mode]
    assert_equal [1, 1], result[:pallets].map { |cargo| cargo[:bill_l] }
    assert_equal [1, 1], result[:pallets].map { |cargo| cargo[:boxes] }
    assert_equal 4, result[:total_units]
    assert_equal 20, result[:total_fee]
    assert_in_delta result[:total_fee], result[:sku_totals].sum { |row| row[:known_fee] }
  end

  test "accepts thirty boxes and rejects thirty one or an overweight carton" do
    assert_equal 30, Ec::PalletPlans::BoxPacking.new(items: [item(quantity: 30)]).call[:pallets].size
    [[{ quantity: 31 }, :box_count_limit], [{ weight: 25.01 }, :box_weight_limit]].each do |attrs, key|
      error = assert_raises(Ec::PalletPlans::Error) { Ec::PalletPlans::BoxPacking.new(items: [item(**attrs)]).call }
      assert_equal key, error.key
    end
  end

  test "six distinct SKUs do not inherit the five SKU pallet restriction" do
    items = 6.times.map { |index| item(sku_code: "BOX-#{index}", quantity: 1) }
    result = Ec::PalletPlans::BoxPacking.new(items: items).call
    assert_equal 6, result[:pallets].size
    assert_equal (0..5).to_a, result[:pallets].flat_map { |cargo| cargo[:zones].map { |zone| zone[:item_index] } }
    assert_nil result[:total_fee]
  end
end
