require "test_helper"
require_relative "../../support/book_ledger_fixtures"

class Ec::InventoryFbsOrdersQueryTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  def fbs_order(business_status:, return_business_status: "none", quantity: 1, ordered_at: Time.current - 5.days)
    order = ledger_order(platform: "wb", status: "delivered", quantity: quantity, ordered_at: ordered_at,
      source_status: "sold", source_substatus: "complete")
    order.fulfillments.first.update_columns(
      business_status: business_status, return_business_status: return_business_status
    )
    order
  end

  test "lists the orders of one cell, newest first, with pagination" do
    older = fbs_order(business_status: "delivered", ordered_at: 3.days.ago)
    newer = fbs_order(business_status: "delivered", ordered_at: 1.day.ago, quantity: 2)
    fbs_order(business_status: "cancelled")

    result = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", page: 1
    ).call

    assert_equal [ newer.external_order_id, older.external_order_id ],
      result[:rows].map { |row| row[:fulfillment_number] }
    assert_equal [ 2, 1 ], result[:rows].map { |row| row[:quantity] }
    assert_equal "wb", result[:rows].first[:platform]
    assert_equal @wb_store.store_name, result[:rows].first[:store_name]
    assert_equal({ page: 1, per_page: 20, total_count: 2, total_pages: 1 }, result[:pagination])
  end

  test "paginates and clamps the page" do
    21.times { fbs_order(business_status: "delivered") }

    second = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", page: 2
    ).call
    clamped = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", page: 99
    ).call

    assert_equal 1, second[:rows].size
    assert_equal 21, second.dig(:pagination, :total_count)
    assert_equal 2, clamped.dig(:pagination, :page)
  end
end
