require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::Inventory::LedgerDiffTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  test "reports legacy and ledger book stock side by side" do
    ledger_batch(100)
    ledger_order(platform: "wb", status: "delivered", quantity: 10)
    # Stale processing order: legacy deducts it, the ledger does not.
    ledger_order(platform: "wb", status: "processing", quantity: 4, ordered_at: Time.current - 100.days)

    row = Ec::Inventory::LedgerDiff.call(sku_codes: [ @sku.sku_code ]).sole

    assert_equal @sku.sku_code, row[:sku_code]
    assert_equal 86, row[:legacy]
    assert_equal 90, row[:ledger]
    assert_equal 4, row[:diff]
    assert_equal 4, row[:stale_open]
  end
end
