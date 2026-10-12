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

  test "unattributed_summary lists non-cancelled order items without a bound product" do
    before = Ec::Inventory::OrderCompleteness.unattributed_summary(limit: 1_000_000)
    unbound_id = "UNBOUND-#{@token}"
    cancelled_id = "CANCELLED-#{@token}"

    ledger_order(platform: "ozon", status: "delivered", quantity: 4, platform_sku_id: unbound_id)
    ledger_order(platform: "ozon", status: "cancelled", quantity: 9, platform_sku_id: cancelled_id)
    # Attributed orders must not show up as unattributed.
    ledger_order(platform: "ozon", status: "delivered", quantity: 2)

    after = Ec::Inventory::OrderCompleteness.unattributed_summary(limit: 1_000_000)

    assert_equal before[:quantity] + 4, after[:quantity]
    assert_equal before[:products] + 1, after[:products]
    row = after[:top].find { |entry| entry[:platform_sku_id] == unbound_id }
    assert_equal({ platform: "ozon", platform_sku_id: unbound_id, quantity: 4 }, row)
    assert_nil after[:top].find { |entry| entry[:platform_sku_id] == cancelled_id }
  end

  test "unattributed_summary caps the top list while keeping the totals" do
    ledger_order(platform: "ozon", status: "delivered", quantity: 1, platform_sku_id: "UNBOUND-A-#{@token}")
    ledger_order(platform: "ozon", status: "delivered", quantity: 1, platform_sku_id: "UNBOUND-B-#{@token}")

    full = Ec::Inventory::OrderCompleteness.unattributed_summary(limit: 1_000_000)
    capped = Ec::Inventory::OrderCompleteness.unattributed_summary(limit: 1)

    assert_equal 1, capped[:top].size
    assert_equal full[:quantity], capped[:quantity]
    assert_equal full[:products], capped[:products]
  end
end
