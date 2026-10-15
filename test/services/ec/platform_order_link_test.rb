require "test_helper"

class EcPlatformOrderLinkTest < ActiveSupport::TestCase
  Order = Struct.new(:platform, :fulfillments)
  Fulfillment = Struct.new(:fulfillment_type, :external_fulfillment_id, :business_status)

  test "an ozon fbs posting opens its card in the cabinet" do
    order = Order.new("ozon", [ Fulfillment.new("fbs", "0128619527-0157-1", "delivered") ])

    assert_equal "https://seller.ozon.ru/app/postings/fbs?postingDetails=0128619527-0157-1",
      Ec::PlatformOrderLink.exact_url(order)
    assert_nil Ec::PlatformOrderLink.list_url(order)
  end

  test "an ozon fbo posting has no card in the cabinet" do
    order = Order.new("ozon", [ Fulfillment.new("fbo", "0128619527-0157-1", "delivered") ])

    assert_nil Ec::PlatformOrderLink.exact_url(order)
    assert_nil Ec::PlatformOrderLink.list_url(order)
  end

  test "an order with an fbo and an fbs posting links the fbs one" do
    order = Order.new("ozon", [ Fulfillment.new("fbo", "FBO-1", "delivered"), Fulfillment.new("fbs", "FBS-1", "delivered") ])

    assert_equal "https://seller.ozon.ru/app/postings/fbs?postingDetails=FBS-1", Ec::PlatformOrderLink.exact_url(order)
  end

  test "a wildberries fbs order links the cabinet tab that holds it, never a single order" do
    {
      "awaiting_assembly" => "new-tasks", "awaiting_dispatch" => "on-assembly", "in_delivery" => "on-delivery",
      "delivered" => "archived", "returned" => "archived", "cancelled" => "canceled"
    }.each do |business_status, tab|
      order = Order.new("wb", [ Fulfillment.new("fbs", "SRID-1", business_status) ])

      assert_nil Ec::PlatformOrderLink.exact_url(order)
      assert_equal "https://seller.wildberries.ru/marketplace-orders-fbs/#{tab}", Ec::PlatformOrderLink.list_url(order)
    end
  end

  test "a wildberries order without an fbs fulfillment or an unknown status has no cabinet link" do
    assert_nil Ec::PlatformOrderLink.list_url(Order.new("wb", [ Fulfillment.new("fbw", "SRID-1", "delivered") ]))
    assert_nil Ec::PlatformOrderLink.list_url(Order.new("wb", [ Fulfillment.new("fbs", "SRID-1", "needs_review") ]))
    assert_nil Ec::PlatformOrderLink.list_url(Order.new("wb", []))
  end
end
