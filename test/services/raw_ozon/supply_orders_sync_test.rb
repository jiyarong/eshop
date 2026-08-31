require "test_helper"
require "securerandom"

class RawOzonSupplyOrdersSyncTest < ActiveSupport::TestCase
  class FakeOzonClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(path, body)
      @requests << [path, body]
      @responses.shift || {}
    end
  end

  test "sync requests every supply state and stores the Ozon creation date" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-supply-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    created_date = "2026-07-29T01:14:10.040397Z"
    client = FakeOzonClient.new([
      { "order_ids" => ["119923443"], "last_id" => "" },
      {
        "orders" => [{
          "order_id" => "119923443",
          "state" => "ACCEPTANCE_AT_STORAGE_WAREHOUSE",
          "created_date" => created_date,
          "timeslot" => {},
          "supplies" => [{
            "state" => "ACCEPTANCE_AT_STORAGE_WAREHOUSE",
            "bundle_id" => "bundle-1",
            "supply_id" => 2_000_064_845_539,
            "macrolocal_cluster_id" => "4007"
          }]
        }]
      },
      { "items" => [{ "sku" => 123_456, "quantity" => 36 }], "has_next" => false }
    ])
    sync = RawOzon::DailySync.new(account, days: 2)
    sync.instance_variable_set(:@client, client)
    sync.define_singleton_method(:sleep) { |_| }
    RawOzon::SupplyOrder.create!(
      account: account,
      supply_order_id: "119923443",
      status: "IN_TRANSIT",
      items: {},
      raw_json: {},
      created_at: nil
    )

    assert_equal 1, sync.sync_supply_orders

    list_request = client.requests.first
    assert_equal "/v3/supply-order/list", list_request.first
    assert_equal RawOzon::Syncs::SupplyOrders::SUPPLY_STATES, list_request.last.dig(:filter, :states)

    order = RawOzon::SupplyOrder.find_by!(account: account, supply_order_id: "119923443")
    assert_equal "ACCEPTANCE_AT_STORAGE_WAREHOUSE", order.status
    assert_equal({ "123456" => 36 }, order.items)
    assert_equal Time.zone.parse(created_date), order.created_at
    item = order.supply_order_items.sole
    assert_equal 2_000_064_845_539, item.ozon_supply_id
    assert_equal "bundle-1", item.bundle_id
    assert_equal 123_456, item.platform_sku_id
    assert_equal 36, item.quantity
    assert_equal 4007, item.macrolocal_cluster_id
  ensure
    RawOzon::SupplyOrderItem.where(supply_order_id: RawOzon::SupplyOrder.where(account_id: account&.id)).delete_all
    RawOzon::SupplyOrder.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end
end
