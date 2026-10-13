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
    assert_equal 3, result[:total_quantity]
  end

  test "store_id restricts the list and the total quantity to one store" do
    wb_order = fbs_order(business_status: "delivered", quantity: 4)
    ozon_order = ledger_order(platform: "ozon", status: "delivered", quantity: 9)
    ozon_order.fulfillments.first.update_columns(business_status: "delivered", return_business_status: "none")

    all_stores = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none"
    ).call
    wb_only = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", store_id: @wb_store.id
    ).call
    ozon_only = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", store_id: @ozon_store.id.to_s
    ).call
    ignored = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", store_id: "abc"
    ).call

    assert_equal 13, all_stores[:total_quantity]
    assert_equal 4, wb_only[:total_quantity]
    assert_equal [ wb_order.external_order_id ], wb_only[:rows].map { |row| row[:fulfillment_number] }
    assert_equal 9, ozon_only[:total_quantity]
    assert_equal [ ozon_order.external_order_id ], ozon_only[:rows].map { |row| row[:fulfillment_number] }
    assert_equal 13, ignored[:total_quantity]
  end

  test "paginates and clamps the page" do
    21.times { |index| fbs_order(business_status: "delivered", quantity: index + 1) }

    first = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", page: 1
    ).call
    second = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", page: 2
    ).call
    clamped = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", page: 99
    ).call

    assert_equal 1, second[:rows].size
    assert_equal 21, second.dig(:pagination, :total_count)
    assert_equal 231, first[:total_quantity]
    assert_equal 231, second[:total_quantity]
    assert_equal 231, clamped[:total_quantity]
    assert_equal 2, clamped.dig(:pagination, :page)
  end
end
