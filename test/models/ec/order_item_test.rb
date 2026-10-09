require "test_helper"

class Ec::OrderItemTest < ActiveSupport::TestCase
  test "names the commission base price after the platform-neutral price columns" do
    item = Ec::OrderItem.new(unit_price: 1450.05, currency_code: "RUB", buyer_paid_unit_price: 1131.1, buyer_currency_code: "RUB")

    assert_equal BigDecimal("1450.05"), item.commission_base_unit_price
    assert_equal "RUB", item.commission_base_currency_code
    assert_equal BigDecimal("1131.1"), item.buyer_paid_unit_price
  end
end
