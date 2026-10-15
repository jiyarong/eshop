require "test_helper"

class PalletPacking::CalculatorTest < ActiveSupport::TestCase
  def item(code = "PALLET-A", **attributes)
    { sku_code: code, length: 40, width: 30, height: 20, weight: 10, pcs: 4, unit_volume_l: 3 }.merge(attributes)
  end

  def calculate(items, profile: "ozon_fbo", settings: {})
    PalletPacking::Calculator.new(profile: profile, items: items, settings: settings).call
  end

  test "recommends a non-overlapping stable partition covering every selected SKU" do
    result = calculate([item, item("PALLET-B", length: 30, width: 20, height: 25), item("PALLET-C", weight: 5)])
    assert_equal 1, result[:pallets].size
    assert result[:sku_totals].all? { |row| row[:boxes].positive? }
    assert_geometry(result)
  end

  test "respects exact quantities and accounts for fixed costs only once" do
    result = calculate([item(quantity: 5, length: 120, width: 80, height: 100, weight: 200)], settings: { route_rate: 0, fixed_fee: 546 })
    assert_equal 3, result[:pallets].size
    assert_equal 5, result[:total_boxes]
    assert_equal 20, result[:total_units]
    assert_equal [546, 0, 0], result[:pallets].map { |pallet| pallet[:breakdown][:fixed] }
    assert_in_delta 546, result[:total_fee]
    assert_geometry(result)
  end

  test "WB splits five selected barcodes into pallets with no more than three" do
    result = calculate(5.times.map { |index| item("PALLET-#{index}", quantity: 2) }, profile: "wb_mono")
    assert_equal 10, result[:total_boxes]
    assert result[:pallets].all? { |pallet| pallet[:zones].size <= 3 }
    assert result[:sku_totals].all? { |row| row[:boxes] == 2 }
    assert_geometry(result)
  end

  test "WB recommendation represents all five selected SKUs" do
    result = calculate(5.times.map { |index| item("PALLET-#{index}") }, profile: "wb_piece")
    assert_equal 2, result[:pallets].size
    assert result[:sku_totals].all? { |row| row[:boxes].positive? }
    assert_geometry(result)
  end

  test "a heavy SKU can ship alone when two SKUs cannot share the weight limit" do
    result = calculate([item(weight: 400, quantity: 1), item("PALLET-B", weight: 400, quantity: 1)], profile: "wb_mono")
    assert_equal 2, result[:pallets].size
    assert_equal 2, result[:total_boxes]
    assert_geometry(result)
  end

  test "FBS counts merchandise units and includes pallet tare in weight limit" do
    result = calculate([item(weight: 25, pcs: 6, quantity: 2)], profile: "ozon_fbs", settings: { weight: 60, handling_rate: 10 })
    assert_equal 2, result[:pallets].size
    assert_equal 12, result[:total_units]
    assert_in_delta 120, result[:total_fee]
    assert result[:pallets].all? { |pallet| pallet[:gross_weight] <= 60 }
  end

  test "FBO weight limit applies to cargo and not to pallet tare" do
    result = calculate([item(weight: 790, quantity: 1)])
    assert_equal 815, result[:pallets].first[:gross_weight]
  end

  test "tipping requires explicit permission" do
    attrs = item(length: 60, width: 50, height: 110, quantity: 1)
    assert_raises(PalletPacking::Calculator::InvalidInput) { calculate([attrs], settings: { height: 100 }) }
    result = calculate([attrs.merge(rotatable: true)], settings: { height: 100 })
    assert_equal 1, result[:total_boxes]
    assert_geometry(result)
  end

  test "combines two horizontal orientations to fill a layer with six 50 by 30 cartons" do
    result = calculate([item(length: 50, width: 30, height: 20)], settings: { height: 34.5 })
    assert_equal 6, result[:total_boxes]
    assert_equal 2, result[:pallets].first[:zones].first[:pattern].size
    assert_geometry(result)
  end

  test "FBO billing uses merchandise volume rather than the exterior pallet volume" do
    result = calculate([item(quantity: 2, unit_volume_l: 0.2)], settings: { route_rate: 12 })
    pallet = result[:pallets].first
    assert_in_delta 1.6, pallet[:goods_l]
    assert_equal 1900, pallet[:bill_l]
    assert_in_delta 22_800, pallet[:breakdown][:route]
    assert_in_delta result[:total_fee], result[:sku_totals].sum { |row| row[:known_fee] }
  end

  test "missing data produces an incomplete fee and never a fabricated zero total" do
    result = calculate([item(quantity: 2, unit_volume_l: nil)])
    assert_nil result[:total_fee]
    assert_equal %i[goods_volume route_rate], result[:missing]
    assert_nil result[:pallets].first[:bill_l]
    assert_equal 2, result[:total_boxes]
    result = calculate([item(quantity: 2)], settings: { route_rate: 0 })
    assert_equal 0, result[:total_fee]
  end

  test "rounds actual merchandise liters above the minimum and does not discount pickup or vehicle fees" do
    result = calculate([item(length: 120, width: 80, height: 200, pcs: 1, unit_volume_l: 1900.1, quantity: 1)],
      settings: { route_rate: 8, pickup: true, discount: 100, fixed_fee: 546 })
    pallet = result[:pallets].first
    assert_equal 1901, pallet[:bill_l]
    assert_equal 0, pallet[:breakdown][:route]
    assert_in_delta 1901 * 1.55, pallet[:breakdown][:pickup]
    assert_in_delta 1901 * 1.55 + 546, result[:total_fee]
  end

  test "sorting fees belong to each SKU and shared fees sum to the shipment cost" do
    result = calculate([item(quantity: 1), item("PALLET-B", quantity: 1, unit_volume_l: 1, pcs: 2)], settings: { route_rate: 8, fixed_fee: 50 })
    pallet = result[:pallets].first
    assert_equal 2, pallet[:zones].size
    assert_in_delta 4 * 7 + 2 * 5, pallet[:breakdown][:handling]
    assert_in_delta result[:total_fee], result[:sku_totals].sum { |row| row[:known_fee] }
  end

  test "Fashion exemption only applies to sorting by composition" do
    items = [item(quantity: 1, fashion: true), item("PALLET-B", quantity: 1, fashion: true)]
    result = calculate(items, settings: { route_rate: 0 })
    assert_equal 0, result[:total_fee]
    result = calculate(items, settings: { route_rate: 0, sorting: "zones" })
    assert_in_delta 120, result[:total_fee]
  end

  test "WB current receiving fee is free and mono storage is charged per pallet" do
    result = calculate([item(quantity: 1)], profile: "wb_mono", settings: { storage_days: 10 })
    assert_in_delta 425, result[:total_fee]
    assert_equal 0, result[:pallets].first[:breakdown][:handling]
    result = calculate([item(quantity: 1)], profile: "wb_piece", settings: { storage_days: 10 })
    assert_in_delta 12 * 0.08 * 1.7 * 10, result[:total_fee]
  end

  test "rejects missing, invalid and mixed quantities and relaxed platform limits" do
    [
      -> { calculate([]) },
      -> { calculate(6.times.map { |index| item(index.to_s) }) },
      -> { calculate([item, item]) },
      -> { calculate([item, item("PALLET-B", quantity: 1)]) },
      -> { calculate([item(pcs: nil)]) },
      -> { calculate([item(quantity: 1.5)]) },
      -> { calculate([item(quantity: "bad")]) },
      -> { calculate([item(weight: "NaN")]) },
      -> { calculate([item], settings: { height: 221 }) },
      -> { calculate([item], settings: { overhang: 3 }) },
      -> { calculate([item(weight: 26)], profile: "wb_piece") },
      -> { calculate([item(weight: 36)], profile: "ozon_fbs") }
    ].each { |operation| assert_raises(PalletPacking::Calculator::InvalidInput, &operation) }
  end

  private

  def assert_geometry(result)
    rule = PalletPacking::Rules::PROFILES.fetch(result[:profile])
    result[:pallets].each do |pallet|
      assert_operator pallet[:height], :<=, result[:settings][:height] + 0.00001
      assert_operator rule[:gross_weight] ? pallet[:gross_weight] : pallet[:weight], :<=, result[:settings][:weight] + 0.00001
      previous_edge = 0
      pallet[:zones].each do |zone|
        assert_operator zone[:offset], :>=, previous_edge
        previous_edge = zone[:offset] + zone[:span]
        span, depth = zone[:swap] ? [80, 120] : [120, 80]
        assert_operator previous_edge, :<=, span + result[:settings][:overhang] * 2 + 0.00001
        zone[:pattern].each do |grid|
          assert_operator grid[:y] + grid[:rows] * grid[:width], :<=, depth + result[:settings][:overhang] * 2 + 0.00001
          assert_operator grid[:columns] * grid[:length], :<=, zone[:span] + 0.00001
        end
        zone[:pattern].each_cons(2) { |first, second| assert_operator second[:y], :>=, first[:y] + first[:rows] * first[:width] }
        assert_operator zone[:count], :<=, zone[:per_layer] * zone[:layers]
        assert_operator zone[:count], :>, zone[:per_layer] * (zone[:layers] - 1)
      end
    end
  end
end
