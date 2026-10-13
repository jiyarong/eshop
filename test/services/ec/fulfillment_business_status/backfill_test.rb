require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::FulfillmentBusinessStatus::BackfillTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  def scoped_run(**options)
    Ec::FulfillmentBusinessStatus::Backfill.run(
      store_ids: [ @wb_store.id, @ozon_store.id ], **options
    )
  end

  test "dry run reports differences without writing" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")

    result = scoped_run(dry_run: true)

    assert_equal 1, result[:checked]
    assert_equal 1, result[:changed]
    assert_equal [ "needs_review", "none" ], result[:samples].first[:from]
    assert_equal [ "delivered", "none" ], result[:samples].first[:to]
    assert_equal "needs_review", order.fulfillments.first.reload.business_status
  end

  test "backfill writes statuses and is idempotent" do
    order = ledger_order(platform: "wb", status: "delivered", source_status: "sold", source_substatus: "complete")
    ledger_order(platform: "ozon", status: "processing", source_status: "awaiting_packaging",
      source_substatus: "posting_created")

    first = scoped_run
    second = scoped_run

    assert_equal 2, first[:changed]
    assert_equal 0, second[:changed]
    assert_equal "delivered", order.fulfillments.first.reload.business_status
    assert_equal "delivered", order.reload.business_status
  end
end
