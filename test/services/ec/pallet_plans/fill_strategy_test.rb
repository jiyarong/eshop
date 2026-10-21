require "test_helper"

class Ec::PalletPlans::FillStrategyTest < ActiveSupport::TestCase
  def item(**overrides)
    { sku_code: "FILL", length: 40, width: 40, height: 60, weight: 5, pcs: 1,
      unit_volume_l: 1, quantity: 14, ozon_size_category: "normal" }.merge(overrides)
  end

  def fill(items: [item], maximum: 18, enabled: true, settings: {}, shipping: {}, stock_overrides: {})
    base = Ec::PalletPlans::Packing.new(items: items, settings: { height: 194.5, route_rate: 5 }.merge(settings)).call
    limits = items.to_h { |entry| [entry[:sku_code], stock_overrides.fetch(entry[:sku_code], maximum)] }
    result = Ec::PalletPlans::FillStrategy.new(items: items, stock_limits: limits, result: base, enabled: enabled, shipping: shipping).call
    [base, result]
  end

  test "fills fourteen to eighteen within the same pallet and route fee" do
    base, result = fill
    assert_equal 18, result[:total_boxes]
    assert_equal 1, result[:pallets].size
    assert_equal base[:total_fee], result[:total_fee]
    assert_equal [{ sku_code: "FILL", from_boxes: 14, to_boxes: 18, added_units: 4 }], result[:fill][:changes]
    assert_equal [18], result[:items].map { |entry| entry[:quantity] }
  end

  test "preserves unequal starting proportions instead of filling the highest shortage SKU first" do
    items = [item(sku_code: "FILL-A", quantity: 2), item(sku_code: "FILL-B", quantity: 4)]
    base, result = fill(items: items, maximum: 50)

    assert_equal [6, 12], result[:items].map { |entry| entry[:quantity] }
    assert_equal base[:pallets].size, result[:pallets].size
    assert_equal base[:pallets].sum { |pallet| pallet[:bill_l] }, result[:pallets].sum { |pallet| pallet[:bill_l] }
    assert_equal [6, 12], items.map { |entry| entry[:quantity] }
    assert_equal [4, 8], result[:fill][:changes].map { |change| change[:added_units] }
  end

  test "rounds proportional quantities fairly and independently of manifest ordering" do
    quantities = { "FILL-A" => 1, "FILL-B" => 2, "FILL-C" => 4 }
    [quantities.to_a, quantities.to_a.reverse].each do |entries|
      items = entries.map { |code, quantity| item(sku_code: code, quantity: quantity, length: 20, width: 20, height: 20) }
      _, result = fill(items: items, maximum: 50, settings: { weight: 90 })

      assert_equal({ "FILL-A" => 3, "FILL-B" => 5, "FILL-C" => 10 },
        result[:items].to_h { |entry| [entry[:sku_code], entry[:quantity]] })
    end
  end

  test "continues filling eligible SKUs after one reaches its stock limit" do
    items = [item(sku_code: "FILL-A", quantity: 2, length: 20, width: 20, height: 20),
      item(sku_code: "FILL-B", quantity: 4, length: 20, width: 20, height: 20)]
    _, result = fill(items: items, maximum: 50, settings: { weight: 90 },
      stock_overrides: { "FILL-A" => 3 })

    assert_equal [3, 15], result[:items].map { |entry| entry[:quantity] }
    assert_equal :stock, result[:fill][:limits].find { |limit| limit[:sku_code] == "FILL-A" }[:reason]
    assert_equal 1, result[:pallets].size
  end

  test "fills existing multiple pallets beyond a SKU single-pallet capacity" do
    base, result = fill(items: [item(quantity: 20)], maximum: 100)

    assert_equal 36, result[:total_boxes]
    assert_equal 2, result[:pallets].size
    assert_equal base[:pallets].sum { |pallet| pallet[:bill_l] }, result[:pallets].sum { |pallet| pallet[:bill_l] }
    assert_equal :pallet_capacity, result[:fill][:limits].sole[:reason]
  end

  test "keeps filling smaller cartons when a proportional candidate no longer fits" do
    items = [item(sku_code: "FILL-A", quantity: 1, length: 20, width: 20, height: 20, weight: 50),
      item(sku_code: "FILL-B", quantity: 1, length: 20, width: 20, height: 20)]
    base, result = fill(items: items, maximum: 50, settings: { weight: 70 })

    assert_equal [1, 4], result[:items].map { |entry| entry[:quantity] }
    assert_equal base[:pallets].size, result[:pallets].size
    assert_equal base[:pallets].sum { |pallet| pallet[:bill_l] }, result[:pallets].sum { |pallet| pallet[:bill_l] }
    assert_equal :pallet_capacity, result[:fill][:limits].find { |limit| limit[:sku_code] == "FILL-A" }[:reason]
  end

  test "stops safely when another carton would exceed the platform pallet count" do
    items = %w[FILL-A FILL-B].map do |code|
      item(sku_code: code, quantity: 20, length: 120, width: 80, height: 180)
    end
    base, result = fill(items: items, maximum: 100)

    assert_equal 40, base[:pallets].size
    assert_equal [20, 20], result[:items].map { |entry| entry[:quantity] }
    assert_empty result[:fill][:changes]
    assert_equal [:pallet_capacity], result[:fill][:limits].pluck(:reason).uniq
  end

  test "caps at stock and never adds a pallet" do
    _, result = fill(maximum: 17)
    assert_equal 17, result[:total_boxes]
    _, result = fill(maximum: 100)
    assert_equal 18, result[:total_boxes]
    assert_equal 1, result[:pallets].size
  end

  test "fills mixed SKUs despite sorting fees when the billed transport volume stays the same" do
    items = [item(sku_code: "FILL-A", quantity: 7), item(sku_code: "FILL-B", quantity: 7)]
    base, result = fill(items: items, maximum: 17)

    assert_equal 18, result[:total_boxes]
    assert_equal [9, 9], result[:items].map { |entry| entry[:quantity] }
    assert_equal base[:pallets].sum { |pallet| pallet[:bill_l] }, result[:pallets].sum { |pallet| pallet[:bill_l] }
    assert_operator result[:known_fee], :>, base[:known_fee]
    assert_equal result[:known_fee] - base[:known_fee], result[:fill][:additional_known_fee]
    assert_equal 1, result[:pallets].size
  end

  test "does not fill beyond paid litres or add configured pickup fees" do
    [ [{ items: [item(unit_volume_l: 150)] }, :billable_volume], [{ settings: { pickup: true } }, :point_handling],
      [{ items: [item(unit_volume_l: nil)] }, :goods_volume] ].each do |options, reason|
      _, result = fill(**options)
      assert_equal 14, result[:total_boxes]
      assert_empty result[:fill][:changes]
      assert_equal reason, result[:fill][:skipped_reason] || result[:fill][:limits].sole[:reason]
    end
  end

  test "fills within the same rounded pallet pickup handling volume" do
    base, result = fill(items: [item(unit_volume_l: 0.2)], maximum: 18, shipping: { point_type: "pickup" })
    assert_equal 15, result[:total_boxes]
    assert_equal base[:pallets].sum { |pallet| pallet[:goods_l].ceil }, result[:pallets].sum { |pallet| pallet[:goods_l].ceil }
    assert_equal :point_handling, result[:fill][:limits].sole[:reason]
  end

  test "allows storage cost to change when route volume stays within the paid minimum" do
    base, result = fill(settings: { storage_days: 1 })
    assert_equal 18, result[:total_boxes]
    assert_operator result[:known_fee], :>, base[:known_fee]
  end

  test "does not treat an unknown route rate as zero when billed volume would increase" do
    _, result = fill(items: [item(unit_volume_l: 150)], settings: { route_rate: nil })
    assert_equal 14, result[:total_boxes]
    assert_empty result[:fill][:changes]
  end

  test "disabled filling preserves the exact manifest" do
    base, result = fill(enabled: false)
    assert_equal base[:pallets], result[:pallets]
    assert_equal 14, result[:total_boxes]
    assert_equal :disabled, result[:fill][:skipped_reason]
  end

  test "fills without sales or coverage data" do
    _, result = fill(items: [item(sku_code: "HZX001", quantity: 6)], maximum: 100)

    assert_equal 18, result[:total_boxes]
    assert_equal :pallet_capacity, result[:fill][:limits].sole[:reason]
    assert_equal 100, result[:fill][:limits].sole[:max_boxes]
    assert_equal 12, result[:fill][:changes].sole[:added_units]
    assert_not result[:fill].key?(:max_days)
  end

  test "distinguishes whole-carton stock and pallet capacity" do
    _, result = fill(maximum: 16)
    assert_equal :stock, result[:fill][:limits].sole[:reason]
    _, result = fill(maximum: 100)
    assert_equal :pallet_capacity, result[:fill][:limits].sole[:reason]
  end

  test "upper coverage rounds down and missing range preserves legacy days" do
    range = Ec::PalletPlans::ReplenishmentRange.new(target_days: 28, min_days: 21, max_days: 35)
    assert_equal({ min_boxes: 11, max_boxes: 17 }, range.boxes(daily_sales: 0.5, available: 0,
      inbound: 0, planned_quantity: 0, pcs: 1, allocatable: 100))
    assert_equal 3, range.boxes(daily_sales: 0.5, available: 0, inbound: 0, planned_quantity: 0, pcs: 1, allocatable: 3)[:max_boxes]
    assert_equal [28, 28], Ec::PalletPlans::ReplenishmentRange.new.to_h.values_at(:min_days, :max_days)
    [{ min_days: 29 }, { max_days: 27 }, { min_days: 0 }, { max_days: 181 }, { target_days: "bad" }].each do |options|
      assert_raises(Ec::PalletPlans::Error) { Ec::PalletPlans::ReplenishmentRange.new(**options) }
    end
  end
end
