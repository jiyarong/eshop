require "test_helper"

class Ec::PalletPlans::MaximizeTest < ActiveSupport::TestCase
  def item(**overrides)
    { sku_code: "MAX-A", length: 40, width: 40, height: 60, weight: 5, pcs: 1,
      unit_volume_l: 1, quantity: 2, ozon_size_category: "normal" }.merge(overrides)
  end

  def maximize(items: [item], stock: 100, settings: {})
    base = Ec::PalletPlans::Packing.new(items: items, settings: { height: 194.5 }.merge(settings)).call
    result = Ec::PalletPlans::Maximize.new(items: items, sku_code: "MAX-A", stock_limit: stock, result: base).call
    [base, result]
  end

  test "maximizes mixed geometry while keeping all other SKU quantities" do
    items = [item, item(sku_code: "MAX-B", quantity: 6)]
    base, result = maximize(items: items)

    assert_equal [12, 6], result[:items].pluck(:quantity)
    assert_equal [12, 6], items.pluck(:quantity)
    assert_equal base[:pallets].size, result[:pallets].size
    assert_equal 18, result[:pallets].sum { |pallet| pallet[:zones].sum { |zone| zone[:count] } }
    assert_equal({ sku_code: "MAX-A", from_boxes: 2, to_boxes: 12 }, result[:maximized])
  end

  test "remaining weight limits MAX even with spare geometric space" do
    _, result = maximize(items: [item, item(sku_code: "MAX-B", quantity: 2, weight: 20)], settings: { weight: 70 })

    assert_equal [6, 2], result[:items].pluck(:quantity)
    assert_equal 70, result[:pallets].sole[:weight]
  end

  test "uses arrangement rather than dividing remaining cubic volume" do
    _, result = maximize(items: [item(length: 70, width: 50, height: 60, quantity: 1),
      item(sku_code: "MAX-B", length: 70, width: 50, height: 60, quantity: 1)])

    assert_equal [3, 1], result[:items].pluck(:quantity)
    assert_equal 1, result[:pallets].size
  end

  test "respects allowed carton rotation" do
    fixed = item(length: 80, width: 60, height: 40, quantity: 1)
    _, upright = maximize(items: [fixed.dup])
    _, rotated = maximize(items: [fixed.merge(rotatable: true)])

    assert_equal 8, upright[:total_boxes]
    assert_equal 9, rotated[:total_boxes]
  end

  test "respects stock and preserves metadata used for saving" do
    items = [item(sku_product_id: 42)]
    _, result = maximize(items: items, stock: 7)

    assert_equal 7, result[:total_boxes]
    assert_equal 42, items.sole[:sku_product_id]
    assert_equal 7, items.sole[:quantity]
  end

  test "fills existing multiple pallets without adding a pallet" do
    base, result = maximize(items: [item(quantity: 20)])

    assert_equal 2, base[:pallets].size
    assert_equal 2, result[:pallets].size
    assert_equal 36, result[:total_boxes]
  end

  test "MAX can increase billed volume and works without unit volume" do
    base, result = maximize(items: [item(unit_volume_l: 150)])
    assert_equal 18, result[:total_boxes]
    assert_operator result[:pallets].sole[:bill_l], :>, base[:pallets].sole[:bill_l]

    _, result = maximize(items: [item(unit_volume_l: nil)])
    assert_equal 18, result[:total_boxes]
  end

  test "a full pallet leaves every quantity intact" do
    _, result = maximize(items: [item(quantity: 12), item(sku_code: "MAX-B", quantity: 6)])

    assert_equal [12, 6], result[:items].pluck(:quantity)
    assert_equal 12, result[:maximized][:to_boxes]
  end
end
