require "test_helper"

class Ec::InventoryVolumeSummaryBuilderTest < ActiveSupport::TestCase
  test "sums only positive cubic meter contributions for each stock bucket" do
    rows = [
      {
        incoming_quantity: 10,
        book_stock: 5,
        platform_inbound_stock: 2,
        platform_stock: 3,
        available_stock: 4,
        unit_volume_l: BigDecimal("1.5")
      },
      {
        incoming_quantity: -8,
        book_stock: 9,
        platform_inbound_stock: 4,
        platform_stock: 1,
        available_stock: 1,
        unit_volume_l: BigDecimal("2.0")
      },
      {
        incoming_quantity: 6,
        book_stock: 6,
        platform_inbound_stock: 6,
        platform_stock: 6,
        available_stock: 6,
        unit_volume_l: nil
      },
      {
        incoming_quantity: 7,
        book_stock: 7,
        platform_inbound_stock: 7,
        platform_stock: 7,
        available_stock: 7,
        unit_volume_l: BigDecimal("0")
      }
    ]

    summary = Ec::InventoryVolumeSummaryBuilder.call(rows)

    assert_equal BigDecimal("0.015"), summary[:pending_stock_volume_m3]
    assert_equal BigDecimal("0.0255"), summary[:book_available_stock_volume_m3]
    assert_equal BigDecimal("0.011"), summary[:platform_inbound_stock_volume_m3]
    assert_equal BigDecimal("0.0065"), summary[:platform_stock_volume_m3]
    assert_equal BigDecimal("0.008"), summary[:overseas_available_stock_volume_m3]
  end
end
