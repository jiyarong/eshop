require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::Inventory::BookLedgerTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  test "splits received batches into purchase and adjustment and ignores stocktake and unreceived batches" do
    ledger_batch(30)
    ledger_batch(-4, type: :wb_fbw_offset)
    ledger_batch(-5, type: :physical_stocktake_adjustment)
    ledger_batch(10, status: "ordered")

    entry = ledger_entry

    assert_equal 30, entry[:purchase_quantity]
    assert_equal(-4, entry[:adjustment_quantity])
    assert_equal 26, entry[:received_quantity]
    assert_equal 26, entry[:ledger_total]
  end

  test "only counts batches received on or before as_of" do
    ledger_batch(10, received_on: Date.new(2026, 9, 1))
    ledger_batch(7, received_on: Date.new(2026, 9, 20))

    entry = ledger_entry(as_of: Time.zone.parse("2026-09-15 23:59:59"))

    assert_equal 10, entry[:received_quantity]
  end

  test "composes platform side, own side and sellable from a ledger entry" do
    entry = {
      ledger_total: 20, return_in_transit_quantity: 3, return_at_platform_quantity: 2, unsellable_quantity: 1
    }

    composed = Ec::Inventory::BookLedger.compose(entry, platform_sellable: 6, platform_inbound: 2)

    assert_equal 8, composed[:platform_side]
    assert_equal 12, composed[:own_side]
    assert_equal 12, composed[:sellable]
    assert_equal 6, composed[:platform_sellable]
    assert_equal 2, composed[:platform_inbound]
  end

  test "counts every fulfillment type and excludes cancelled, WB returned and stale open orders" do
    ledger_batch(100)
    ledger_order(platform: "wb", status: "delivered", quantity: 7)
    ledger_order(platform: "wb", status: "delivered", quantity: 5, fulfillment_type: "fbw")
    ledger_order(platform: "ozon", status: "delivered", quantity: 9)
    ledger_order(platform: "ozon", status: "shipped", quantity: 2, fulfillment_type: "fbo")
    ledger_order(platform: "wb", status: "cancelled", quantity: 4)
    ledger_order(platform: "wb", status: "returned", quantity: 3)
    ledger_order(platform: "ozon", status: "returned", quantity: 6)
    ledger_order(platform: "wb", status: "processing", quantity: 8, ordered_at: Time.current - 60.days)
    ledger_order(platform: "wb", status: "processing", quantity: 1, ordered_at: Time.current - 5.days)

    entry = ledger_entry

    assert_equal 30, entry[:gross_sales_quantity]
    assert_equal 8, entry[:stale_open_order_quantity]
    assert_equal 70, entry[:ledger_total]

    wb = entry[:by_store][[ "wb", @wb_store.id ]]
    ozon = entry[:by_store][[ "ozon", @ozon_store.id ]]
    assert_equal 13, wb[:gross_sales_quantity]
    assert_equal 12, wb[:status_counts]["signed"]
    assert_equal 1, wb[:status_counts]["processing"]
    assert_equal 17, ozon[:gross_sales_quantity]
    assert_equal 9, ozon[:status_counts]["signed"]
    assert_equal 2, ozon[:status_counts]["shipping"]
  end

  test "uses the fulfillment status over the order level status" do
    ledger_batch(100)
    ledger_order(platform: "ozon", status: "cancelled", fulfillment_status: "delivered", quantity: 3)
    ledger_order(platform: "ozon", status: "delivered", fulfillment_status: "cancelled", quantity: 2)

    entry = ledger_entry

    assert_equal 3, entry[:gross_sales_quantity]
    assert_equal 97, entry[:ledger_total]
  end

  test "falls back to the order status when an item has no fulfillment" do
    ledger_batch(100)
    ledger_order(platform: "wb", status: "returned", quantity: 2, with_fulfillment: false)
    ledger_order(platform: "wb", status: "delivered", quantity: 4, with_fulfillment: false)

    assert_equal 4, ledger_entry[:gross_sales_quantity]
  end

  test "only counts orders placed on or before as_of" do
    ledger_batch(100)
    ledger_order(platform: "wb", status: "delivered", quantity: 3, ordered_at: Time.zone.parse("2026-09-01 10:00:00"))
    ledger_order(platform: "wb", status: "delivered", quantity: 5, ordered_at: Time.zone.parse("2026-09-20 10:00:00"))

    entry = ledger_entry(as_of: Time.zone.parse("2026-09-15 23:59:59"))

    assert_equal 3, entry[:gross_sales_quantity]
  end
end
