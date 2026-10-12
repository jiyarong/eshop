require "test_helper"
require_relative "../../support/book_ledger_fixtures"

class Ec::SkuInventoryOverviewBatchQueryTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  test "book stock follows the ledger rules" do
    ledger_batch(50)
    ledger_order(platform: "wb", status: "delivered", quantity: 10)
    ledger_order(platform: "wb", status: "processing", quantity: 6, ordered_at: Time.current - 100.days)
    returned = ledger_order(platform: "ozon", status: "delivered", quantity: 4)
    ledger_return(returned, source_status: "ReceivedBySeller", quantity: 3)

    result = Ec::SkuInventoryOverviewBatchQuery.new(skus: [ @sku ]).call.fetch(@sku.sku_code)

    assert_equal 50 - 14 + 3, result[:book_stock]
  end
end
