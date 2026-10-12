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
end
