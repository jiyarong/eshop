require "test_helper"

class Ec::RoiCalculatorTest < ActiveSupport::TestCase
  test "returns roi from profit and cost base formula" do
    result = Ec::RoiCalculator.for_profit_and_cost_base(
      operating_profit: 120,
      cost_base: 400
    )

    assert_in_delta 0.3, result[:roi], 0.000001
  end

  test "returns nil roi when cost base is not positive" do
    result = Ec::RoiCalculator.for_profit_and_cost_base(
      operating_profit: 120,
      cost_base: 0
    )

    assert_equal({ roi: nil }, result)
  end

  test "returns roi and annualized return from html formula" do
    result = Ec::RoiCalculator.call(
      cost: 400,
      total_qty: 200,
      weekly_sales: 12,
      unit_profit: 400,
      len: 52,
      width: 5,
      height: 85,
      storage_fee: 50,
      interest_rate: 1
    )

    assert_in_delta 0.9754378, result[:roi], 0.000001
    assert_in_delta 3.0433660, result[:annualized_return], 0.000001
  end

  test "returns nil values when denominator inputs are invalid" do
    result = Ec::RoiCalculator.call(
      cost: 0,
      total_qty: 200,
      weekly_sales: 12,
      unit_profit: 400,
      len: 52,
      width: 5,
      height: 85,
      storage_fee: 50,
      interest_rate: 1
    )

    assert_nil result[:roi]
    assert_nil result[:annualized_return]
  end
end
