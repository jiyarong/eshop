require "test_helper"
require "securerandom"

class RawWbArchiveOrdersSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :requests

    def initialize(orders_by_month = {})
      @orders_by_month = orders_by_month
      @requests = []
    end

    def get(service, path, params = {})
      @requests << { service:, path:, params: }
      orders = @orders_by_month.fetch([ params.fetch(:year), params.fetch(:month) ], [])
      { "orders" => orders, "next" => 0 }
    end
  end

  setup do
    @token = SecureRandom.hex(6)
    @account = RawWb::SellerAccount.create!(
      name: "wb-archive-orders-#{@token}", api_token: "token-#{@token}", company_type: "small"
    )
    @wb_order_id = 80_000_000_000 + @token.first(6).to_i(16)
  end

  teardown do
    RawWb::Order.where(account_id: @account&.id).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
  end

  test "weekly step reads the current and the three previous calendar months" do
    travel_to Time.zone.local(2026, 10, 15, 12) do
      client = FakeWbClient.new
      sync = RawWb::ArchiveOrdersSync.new(@account, days: 1)
      sync.instance_variable_set(:@client, client)

      sync.sync_recent_archive_orders

      assert_equal [ [ 2026, 7 ], [ 2026, 8 ], [ 2026, 9 ], [ 2026, 10 ] ],
        client.requests.map { |request| request[:params].values_at(:year, :month) }
      assert_equal [ "/api/marketplace/v3/fbs/orders/archive" ], client.requests.map { |r| r[:path] }.uniq
    end
    assert_equal [ :sync_recent_archive_orders ], RawWb::ArchiveOrdersSync::STEPS
  end

  test "archive rows replace a stale status without touching g_number or the creation time" do
    created_at = Time.utc(2026, 6, 20, 8)
    RawWb::Order.create!(
      account: @account, wb_order_id: @wb_order_id, srid: "srid-#{@token}", delivery_type: "fbs",
      nm_id: 123, supplier_status: "new", wb_status: "waiting", price: 10, converted_price: 10,
      currency_code: 643, required_meta: [], optional_meta: [], is_zero_order: false,
      g_number: "G-#{@token}", created_at: created_at, updated_at: created_at, synced_at: created_at
    )
    archived = {
      "id" => @wb_order_id, "rid" => "srid-#{@token}", "createdAt" => "2026-06-21T00:00:00Z",
      "product" => { "nmId" => 123, "skus" => [ "2000000000001" ] },
      "status" => { "supplierStatus" => "complete", "wbStatus" => "sold" },
      "priceInfo" => { "price" => 1000, "convertedPrice" => 1000, "currencyCode" => 643 }
    }
    client = FakeWbClient.new([ 2026, 6 ] => [ archived ])
    sync = RawWb::ArchiveOrdersSync.new(@account, days: 1)
    sync.instance_variable_set(:@client, client)

    sync.sync_archive_orders(from_month: Date.new(2026, 6, 1))

    order = RawWb::Order.find_by!(account: @account, wb_order_id: @wb_order_id)
    assert_equal "complete", order.supplier_status
    assert_equal "sold", order.wb_status
    assert_equal "G-#{@token}", order.g_number
    assert_equal created_at, order.created_at
  end
end
