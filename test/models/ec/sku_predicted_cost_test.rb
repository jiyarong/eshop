require "test_helper"

class Ec::SkuPredictedCostTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "PRED-#{@token}", product_name: "预测成本 SKU")
  end

  teardown do
    Ec::SkuPredictedCost.where(sku_code: @sku.sku_code).delete_all if defined?(Ec::SkuPredictedCost)
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "defaults currency to CNY and belongs to sku" do
    predicted_cost = Ec::SkuPredictedCost.create!(
      sku_code: @sku.sku_code,
      cost_money: 12.34,
      effective_from: Date.new(2026, 6, 1)
    )

    assert_equal "CNY", predicted_cost.cost_currency
    assert_equal 12.34.to_d, predicted_cost.cost_money
    assert_equal @sku, predicted_cost.sku
  end

  test "rejects end date before start date" do
    predicted_cost = Ec::SkuPredictedCost.new(
      sku_code: @sku.sku_code,
      cost_money: 12.34,
      effective_from: Date.new(2026, 6, 10),
      effective_to: Date.new(2026, 6, 1)
    )

    assert_not predicted_cost.valid?
    assert_includes predicted_cost.errors[:effective_to], "不能早于开始日期"
  end

  test "sku returns predicted cost effective on date" do
    old_cost = Ec::SkuPredictedCost.create!(
      sku_code: @sku.sku_code,
      cost_money: 10,
      effective_from: Date.new(2026, 6, 1),
      effective_to: Date.new(2026, 6, 30)
    )
    current_cost = Ec::SkuPredictedCost.create!(
      sku_code: @sku.sku_code,
      cost_money: 12,
      effective_from: Date.new(2026, 7, 1)
    )

    assert_equal old_cost, @sku.predicted_cost_on(Date.new(2026, 6, 15))
    assert_equal current_cost, @sku.predicted_cost_on(Date.new(2026, 7, 15))
    assert_nil @sku.predicted_cost_on(Date.new(2026, 5, 31))
  end
end
