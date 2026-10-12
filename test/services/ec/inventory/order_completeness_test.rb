require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::Inventory::OrderCompletenessTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  test "counts raw orders and postings that never became orders" do
    before = Ec::Inventory::OrderCompleteness.call

    RawWb::Order.create!(
      account: @wb_account, wb_order_id: 71_000_000_000 + @token.to_i(16), nm_id: 1,
      delivery_type: "fbs", wb_status: "waiting", supplier_status: "new"
    )
    RawOzon::PostingFbs.create!(
      account: @ozon_account, posting_number: "NOFULFILL-#{@token}", status: "delivered",
      raw_json: {}, created_at: Time.current
    )

    after = Ec::Inventory::OrderCompleteness.call

    assert_equal before[:wb_marketplace_orders_without_order] + 1, after[:wb_marketplace_orders_without_order]
    assert_equal before[:ozon_postings_without_fulfillment] + 1, after[:ozon_postings_without_fulfillment]
    assert_equal before[:wb_stats_orders_without_order], after[:wb_stats_orders_without_order]
  end
end
