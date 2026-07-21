require "test_helper"

class Ec::SkuCostTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "COST-EFF-#{@token}")
  end

  teardown do
    Ec::SkuCost.where(sku_code: @sku.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku.sku_code).delete_all
  end

  test "sku can have multiple costs with different effective dates" do
    old_cost = Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      effective_on: Date.new(2026, 1, 1),
      purchase_price_cny: 10
    )
    new_cost = Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      effective_on: Date.new(2026, 7, 1),
      purchase_price_cny: 20
    )

    assert_equal old_cost, @sku.cost_on(Date.new(2026, 6, 30))
    assert_equal new_cost, @sku.cost_on(Date.new(2026, 7, 1))
    assert_nil @sku.cost_on(Date.new(2025, 12, 31))
  end

  test "latest by sku as of returns one latest cost per sku" do
    Ec::SkuCost.create!(sku_code: @sku.sku_code, effective_on: Date.new(2026, 1, 1), purchase_price_cny: 10)
    current_cost = Ec::SkuCost.create!(sku_code: @sku.sku_code, effective_on: Date.new(2026, 6, 1), purchase_price_cny: 15)
    Ec::SkuCost.create!(sku_code: @sku.sku_code, effective_on: Date.new(2026, 8, 1), purchase_price_cny: 20)

    result = Ec::SkuCost.latest_by_sku_as_of([@sku.sku_code], Date.new(2026, 7, 1)).to_a

    assert_equal [current_cost], result
  end

  test "sku cost effective date is unique per sku" do
    Ec::SkuCost.create!(sku_code: @sku.sku_code, effective_on: Date.new(2026, 1, 1), purchase_price_cny: 10)
    duplicate = Ec::SkuCost.new(sku_code: @sku.sku_code, effective_on: Date.new(2026, 1, 1), purchase_price_cny: 12)

    assert_not duplicate.valid?
    assert duplicate.errors[:sku_code].present?
  end
end
