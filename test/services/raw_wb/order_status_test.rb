require "test_helper"

class RawWbOrderStatusTest < ActiveSupport::TestCase
  test "normalizes marketplace status before supplier status" do
    cases = {
      "waiting" => "processing",
      "sorted" => "shipped",
      "ready_for_pickup" => "shipped",
      "sold" => "delivered",
      "canceled" => "cancelled",
      "canceled_by_client" => "cancelled",
      "declined_by_client" => "cancelled",
      "defect" => "cancelled",
      "returned" => "returned"
    }

    cases.each do |wb_status, expected|
      assert_equal expected, RawWb::OrderStatus.normalize(
        wb_status: wb_status,
        supplier_status: "complete"
      )
    end
  end

  test "uses supplier status only when marketplace status is unavailable" do
    assert_equal "shipped", RawWb::OrderStatus.normalize(wb_status: nil, supplier_status: "complete")
    assert_equal "processing", RawWb::OrderStatus.normalize(wb_status: nil, supplier_status: "confirm")
    assert_equal "cancelled", RawWb::OrderStatus.normalize(wb_status: nil, supplier_status: "cancel")
    assert_equal "unknown", RawWb::OrderStatus.normalize(wb_status: "unexpected", supplier_status: "unexpected")
  end
end
