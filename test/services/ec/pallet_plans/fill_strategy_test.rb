require "test_helper"

class Ec::PalletPlans::FillStrategyTest < ActiveSupport::TestCase
  def item(**overrides)
    { sku_code: "FILL", length: 40, width: 40, height: 60, weight: 5, pcs: 1,
      unit_volume_l: 1, quantity: 14, ozon_size_category: "normal" }.merge(overrides)
  end

  def fill(items: [item], maximum: 18, enabled: true, settings: {}, shipping: {}, daily_sales: 0.5, max_days: 36)
    base = Ec::PalletPlans::Packing.new(items: items, settings: { height: 194.5, route_rate: 5 }.merge(settings)).call
    range = Ec::PalletPlans::ReplenishmentRange.new(target_days: 28, min_days: 21, max_days: max_days, fill_free_space: enabled)
    rows = items.map { |entry| { sku_code: entry[:sku_code], shortage: 14, daily_sales: daily_sales, max_boxes: maximum } }
    result = Ec::PalletPlans::FillStrategy.new(items: items, demand_rows: rows, result: base, range: range, shipping: shipping).call
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

  test "caps at stock and coverage and never adds a pallet" do
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

  test "explains why a low-sales SKU has no extra whole carton within maximum coverage" do
    _, result = fill(items: [item(sku_code: "HZX001", quantity: 6)], daily_sales: 0.18, maximum: 6, max_days: 35)

    assert_equal 6, result[:total_boxes]
    assert_empty result[:fill][:changes]
    limit = result[:fill][:limits].sole
    assert_equal "HZX001", limit[:sku_code]
    assert_equal :coverage, limit[:reason]
    assert_equal 6, limit[:max_boxes]
    assert_equal BigDecimal("38.9"), limit[:next_box_days]
  end

  test "preserves the target manifest when whole-carton rounding already exceeds maximum days" do
    _, result = fill(items: [item(quantity: 2, pcs: 5)], daily_sales: 0.18, maximum: 1, max_days: 35)

    assert_equal 2, result[:total_boxes]
    assert_equal :coverage, result[:fill][:limits].sole[:reason]
  end

  test "coverage explanations do not round a breached limit back down to the maximum" do
    _, result = fill(items: [item(quantity: 40, length: 20, width: 20, height: 20)],
      daily_sales: 1.17, maximum: 40, max_days: 35)

    assert_equal :coverage, result[:fill][:limits].sole[:reason]
    assert_equal BigDecimal("35.1"), result[:fill][:limits].sole[:next_box_days]
  end

  test "distinguishes whole-carton stock and pallet capacity from coverage limits" do
    _, result = fill(maximum: 16)
    assert_equal :stock, result[:fill][:limits].sole[:reason]
    _, result = fill(maximum: 100)
    assert_equal :pallet_capacity, result[:fill][:limits].sole[:reason]
    _, result = fill(daily_sales: 0)
    assert_equal :no_sales, result[:fill][:limits].sole[:reason]
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
