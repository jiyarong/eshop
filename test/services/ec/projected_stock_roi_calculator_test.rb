require "test_helper"

class Ec::ProjectedStockRoiCalculatorTest < ActiveSupport::TestCase
  test "returns projected holding-cost roi metrics for valid inputs" do
    result = Ec::ProjectedStockRoiCalculator.call(
      net_sales_quantity: 14,
      operating_profit_cny: BigDecimal("337.5"),
      days_count: 7,
      unit_goods_cost_cny: BigDecimal("10"),
      unit_volume_l: BigDecimal("1.0")
    )

    assert_equal true, result[:calculable]
    assert_in_delta 2.0, result[:average_daily_net_sales].to_f, 0.000001
    assert_in_delta 360.0, result[:projected_stock_qty_180d].to_f, 0.000001
    assert_in_delta 180.0, result[:average_inventory_qty].to_f, 0.000001
    assert_in_delta 5.9393, result[:projected_months_to_clear].to_f, 0.001
    assert_in_delta 106.9, result[:predicted_storage_cost_cny].to_f, 0.1
    assert_in_delta 106.9, result[:predicted_interest_cost_cny].to_f, 0.1
    assert_in_delta 3600.0, result[:cost_base_cny].to_f, 0.000001
    assert_in_delta 123.7, result[:adjusted_operating_net_profit_cny].to_f, 0.2
    assert_in_delta 0.0344, result[:roi].to_f, 0.001
  end

  test "returns blank roi when cost or volume inputs are unusable" do
    missing_cost = Ec::ProjectedStockRoiCalculator.call(
      net_sales_quantity: 14,
      operating_profit_cny: BigDecimal("337.5"),
      days_count: 7,
      unit_goods_cost_cny: nil,
      unit_volume_l: BigDecimal("1.0")
    )

    assert_equal true, missing_cost[:missing_cost]
    assert_equal false, missing_cost[:calculable]
    assert_nil missing_cost[:predicted_storage_cost_cny]
    assert_nil missing_cost[:predicted_interest_cost_cny]
    assert_nil missing_cost[:adjusted_operating_net_profit_cny]
    assert_nil missing_cost[:roi]

    missing_volume = Ec::ProjectedStockRoiCalculator.call(
      net_sales_quantity: 14,
      operating_profit_cny: BigDecimal("337.5"),
      days_count: 7,
      unit_goods_cost_cny: BigDecimal("10"),
      unit_volume_l: BigDecimal("0")
    )

    assert_equal true, missing_volume[:missing_volume]
    assert_equal false, missing_volume[:calculable]
    assert_nil missing_volume[:predicted_storage_cost_cny]
    assert_nil missing_volume[:predicted_interest_cost_cny]
    assert_nil missing_volume[:adjusted_operating_net_profit_cny]
    assert_nil missing_volume[:roi]
  end
end
