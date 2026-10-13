require "test_helper"
require_relative "../../support/book_ledger_fixtures"

class Ec::InventoryFbsStatusMatrixQueryTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  def fbs_fulfillment(platform:, business_status:, return_business_status: "none", quantity: 1, fulfillment_type: "fbs")
    order = ledger_order(platform: platform, status: "delivered", quantity: quantity, fulfillment_type: fulfillment_type)
    order.fulfillments.first.update_columns(
      business_status: business_status, return_business_status: return_business_status
    )
    order
  end

  test "kind classifies a cell by whether the goods left the warehouse and came back" do
    kind = ->(business, ret) { Ec::InventoryFbsStatusMatrixQuery.kind(business, ret) }

    assert_equal "not_left", kind.call("awaiting_assembly", "none")
    assert_equal "not_left", kind.call("awaiting_dispatch", "none")
    assert_equal "not_left", kind.call("needs_review", "none")
    assert_equal "not_left", kind.call("cancelled", "none")
    assert_equal "left", kind.call("in_delivery", "none")
    assert_equal "left", kind.call("delivered", "none")
    assert_equal "left", kind.call("cancelled", "expected")
    assert_equal "left", kind.call("cancelled", "at_platform_side")
    assert_equal "left", kind.call("delivered", "no_physical_return")
    assert_equal "returned", kind.call("delivered", "received_by_seller")
    assert_equal "returned", kind.call("cancelled", "received_by_seller")
    assert_equal "returned", kind.call("awaiting_assembly", "received_by_seller")
  end

  test "anomaly marks combinations that should not occur" do
    anomaly = ->(business, ret) { Ec::InventoryFbsStatusMatrixQuery.anomaly?(business, ret) }

    assert_not anomaly.call("delivered", "received_by_seller")
    assert_not anomaly.call("cancelled", "expected")
    assert anomaly.call("awaiting_assembly", "received_by_seller")
    assert anomaly.call("in_delivery", "at_platform_side")
    assert anomaly.call("delivered", "expected")
  end

  test "sums FBS order item quantities per cell for the sku only" do
    fbs_fulfillment(platform: "wb", business_status: "delivered", quantity: 5)
    fbs_fulfillment(platform: "ozon", business_status: "delivered", quantity: 2)
    fbs_fulfillment(platform: "wb", business_status: "awaiting_assembly", quantity: 3)
    fbs_fulfillment(platform: "wb", business_status: "cancelled", return_business_status: "received_by_seller", quantity: 4)
    fbs_fulfillment(platform: "wb", business_status: "awaiting_assembly", return_business_status: "received_by_seller")
    fbs_fulfillment(platform: "ozon", business_status: "delivered", fulfillment_type: "fbo", quantity: 9)

    result = Ec::InventoryFbsStatusMatrixQuery.new(@sku).call
    cells = result[:cells].to_h { |cell| [ [ cell[:business_status], cell[:return_business_status] ], cell ] }

    assert_equal 7, cells.fetch([ "delivered", "none" ])[:quantity]
    assert_equal "left", cells.fetch([ "delivered", "none" ])[:kind]
    assert_equal 3, cells.fetch([ "awaiting_assembly", "none" ])[:quantity]
    assert_equal 4, cells.fetch([ "cancelled", "received_by_seller" ])[:quantity]
    assert cells.fetch([ "awaiting_assembly", "received_by_seller" ])[:anomaly]
    assert_equal(
      { departed_quantity: 12, not_departed_quantity: 3, returned_quantity: 5, anomaly_quantity: 1, total_quantity: 15 },
      result[:summary]
    )
  end

  test "ignores order items that are not linked to the sku through sku products" do
    order = fbs_fulfillment(platform: "wb", business_status: "delivered", quantity: 6)
    order.items.update_all(platform_sku_id: "UNBOUND-#{@token}", sku_code: @sku.sku_code)

    result = Ec::InventoryFbsStatusMatrixQuery.new(@sku).call

    assert_equal 0, result.dig(:summary, :total_quantity)
  end
end
