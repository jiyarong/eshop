require "test_helper"

class Ec::InventoryReportRowMetricsBuilderTest < ActiveSupport::TestCase
  test "merges daily sales velocity and turnover values into a raw inventory row" do
    raw_row = {
      sku_code: "INV-ROW-1",
      incoming_quantity: 15,
      book_stock: 10,
      platform_stock: 4,
      available_stock: 6
    }

    result = Ec::InventoryReportRowMetricsBuilder.call(
      raw_row,
      metrics: { daily_sales_velocity: BigDecimal("2.5") },
      cache_updated_at: Time.zone.parse("2026-07-04 10:00:00")
    )

    assert_equal BigDecimal("2.5"), result[:daily_sales_velocity]
    assert_equal BigDecimal("4"), result[:turnover_days]
    assert_equal BigDecimal("10"), result[:turnover_days_with_procurement]
    assert_equal Time.zone.parse("2026-07-04 10:00:00"), result[:cache_updated_at]
  end

  test "keeps turnover values blank when daily sales velocity is missing or non-positive" do
    raw_row = {
      sku_code: "INV-ROW-2",
      incoming_quantity: 8,
      book_stock: 12,
      platform_stock: 0,
      available_stock: 12
    }

    blank_velocity = Ec::InventoryReportRowMetricsBuilder.call(raw_row, metrics: {})
    zero_velocity = Ec::InventoryReportRowMetricsBuilder.call(
      raw_row,
      metrics: { daily_sales_velocity: BigDecimal("0") }
    )

    assert_nil blank_velocity[:daily_sales_velocity]
    assert_nil blank_velocity[:turnover_days]
    assert_nil blank_velocity[:turnover_days_with_procurement]

    assert_equal BigDecimal("0"), zero_velocity[:daily_sales_velocity]
    assert_nil zero_velocity[:turnover_days]
    assert_nil zero_velocity[:turnover_days_with_procurement]
  end
end
