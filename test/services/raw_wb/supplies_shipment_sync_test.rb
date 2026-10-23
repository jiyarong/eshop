require "test_helper"
require "securerandom"

class RawWbSuppliesShipmentSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :gets

    def initialize(supplies:, order_ids:)
      @supplies = supplies
      @order_ids = order_ids
      @gets = []
    end

    def get(service, path, params = {})
      @gets << { service: service, path: path, params: params }
      return { "supplies" => @supplies, "next" => 0 } if path == "/api/v3/supplies"

      supply_id = path[%r{/supplies/([^/]+)/order-ids}, 1]
      raise "unexpected GET #{path}" unless supply_id

      { "orderIds" => @order_ids.fetch(supply_id) }
    end
  end

  setup do
    @token = SecureRandom.hex(4).upcase
    @account = RawWb::SellerAccount.create!(name: "wb-ship-#{@token}", api_token: "token-#{@token}", company_type: "small")
    @store = Ec::Store.create!(platform: "wb", store_name: "WB ship #{@token}", company_type: "small", wb_raw_account_id: @account.id)
    @base_id = 8_000_000_000 + @token.to_i(16) % 1_000_000 * 100
    @closed_at = Time.utc(2026, 10, 22, 8, 53, 8)
    @now = Time.utc(2026, 10, 23, 10, 0, 0)
  end

  teardown do
    Ec::OrderFulfillment.where(store_id: @store&.id).delete_all
    Ec::Order.where(store_id: @store&.id).delete_all
    supply_ids = RawWb::Supply.where(account_id: @account&.id).pluck(:id)
    RawWb::SupplyOrder.where(supply_id: supply_ids).delete_all
    RawWb::Supply.where(account_id: @account&.id).delete_all
    RawWb::Order.where(account_id: @account&.id).delete_all
    RawWb::StatsOrder.where(account_id: @account&.id).delete_all
    @store&.destroy
    @account&.destroy
  end

  test "links closed FBS supplies to their orders and stamps the fulfillment shipped_at" do
    order = raw_order(@base_id + 1)
    other = raw_order(@base_id + 2)
    fulfillment = fulfillment_for(order)
    other_fulfillment = fulfillment_for(other)
    client = FakeWbClient.new(
      supplies: [supply_json("WB-GI-#{@token}1", closed_at: @closed_at)],
      order_ids: { "WB-GI-#{@token}1" => [order.wb_order_id, @base_id + 99] }
    )

    run_sync(client)

    supply = RawWb::Supply.find_by!(wb_supply_id: "WB-GI-#{@token}1")
    assert_equal [order.id], RawWb::SupplyOrder.where(supply_id: supply.id).pluck(:order_id)
    assert_equal @closed_at, fulfillment.reload.shipped_at
    assert_nil other_fulfillment.reload.shipped_at
  end

  test "is idempotent and keeps the first supply when an order is shipped twice" do
    order = raw_order(@base_id + 3)
    fulfillment = fulfillment_for(order)
    later = @closed_at + 1.day
    client = FakeWbClient.new(
      supplies: [
        supply_json("WB-GI-#{@token}1", closed_at: @closed_at),
        supply_json("WB-GI-#{@token}2", closed_at: later)
      ],
      order_ids: { "WB-GI-#{@token}1" => [order.wb_order_id], "WB-GI-#{@token}2" => [order.wb_order_id] }
    )

    2.times { run_sync(client) }

    assert_equal 2, RawWb::SupplyOrder.where(order_id: order.id).count
    assert_equal @closed_at, fulfillment.reload.shipped_at
  end

  test "ignores open supplies and supplies closed before the lookback window" do
    order = raw_order(@base_id + 4)
    fulfillment = fulfillment_for(order)
    client = FakeWbClient.new(
      supplies: [
        supply_json("WB-GI-#{@token}1", closed_at: nil, done: false),
        supply_json("WB-GI-#{@token}2", closed_at: @closed_at - 30.days)
      ],
      order_ids: {}
    )

    run_sync(client)

    assert_equal 0, RawWb::SupplyOrder.where(order_id: order.id).count
    assert_nil fulfillment.reload.shipped_at
    assert_equal ["/api/v3/supplies"], client.gets.map { |request| request[:path] }
  end

  test "stamps shipped_at on a fulfillment created after the supply was linked" do
    order = raw_order(@base_id + 5)
    supply = RawWb::Supply.create!(account: @account, wb_supply_id: "WB-GI-#{@token}9", is_done: true, closed_at: @closed_at)
    RawWb::SupplyOrder.create!(supply: supply, order: order)
    fulfillment = fulfillment_for(order)

    assert_equal 1, Ec::OrderImport::WbShippedAt.call(account_id: @account.id)

    assert_equal @closed_at, fulfillment.reload.shipped_at
    assert_equal 0, Ec::OrderImport::WbShippedAt.call(account_id: @account.id)
  end

  test "a cancelled order only counts as shipped when it was cancelled after its supply was closed" do
    after = cancelled_fulfillment(@base_id + 10, supplier_status: "cancel", wb_status: "canceled", cancel_date: @closed_at + 7.days)
    before = cancelled_fulfillment(@base_id + 11, supplier_status: "complete", wb_status: "canceled_by_client", cancel_date: @closed_at - 1.hour)
    unknown = cancelled_fulfillment(@base_id + 12, supplier_status: "cancel", wb_status: "canceled", cancel_date: :no_stats_row)
    declined = cancelled_fulfillment(@base_id + 13, supplier_status: "complete", wb_status: "declined_by_client", cancel_date: :no_stats_row)
    supply = RawWb::Supply.create!(account: @account, wb_supply_id: "WB-GI-#{@token}8", is_done: true, closed_at: @closed_at)
    [after, before, unknown, declined].each { |fulfillment| RawWb::SupplyOrder.create!(supply: supply, order_id: fulfillment.raw_source_id) }

    Ec::OrderImport::WbShippedAt.call(account_id: @account.id)

    assert_equal @closed_at, after.reload.shipped_at
    assert_nil before.reload.shipped_at
    assert_nil unknown.reload.shipped_at
    assert_equal @closed_at, declined.reload.shipped_at
  end

  test "clears shipped_at when a later cancellation turns out to predate the shipment" do
    fulfillment = cancelled_fulfillment(@base_id + 14, supplier_status: "complete", wb_status: "sorted", cancel_date: :no_stats_row)
    supply = RawWb::Supply.create!(account: @account, wb_supply_id: "WB-GI-#{@token}7", is_done: true, closed_at: @closed_at)
    RawWb::SupplyOrder.create!(supply: supply, order_id: fulfillment.raw_source_id)
    Ec::OrderImport::WbShippedAt.call(account_id: @account.id)
    assert_equal @closed_at, fulfillment.reload.shipped_at

    raw = RawWb::Order.find(fulfillment.raw_source_id)
    raw.update_columns(wb_status: "canceled_by_client")
    RawWb::StatsOrder.create!(account: @account, srid: raw.srid, nm_id: 1, order_date: raw.created_at,
      is_cancel: true, cancel_date: @closed_at - 2.hours)
    Ec::OrderImport::WbShippedAt.call(account_id: @account.id)

    assert_nil fulfillment.reload.shipped_at
  end

  private

  def cancelled_fulfillment(wb_order_id, supplier_status:, wb_status:, cancel_date:)
    order = raw_order(wb_order_id)
    order.update_columns(supplier_status: supplier_status, wb_status: wb_status)
    unless cancel_date == :no_stats_row
      RawWb::StatsOrder.create!(account: @account, srid: order.srid, nm_id: 1, order_date: order.created_at,
        is_cancel: true, cancel_date: cancel_date)
    end
    fulfillment_for(order)
  end

  def run_sync(client)
    travel_to(@now) do
      sync = RawWb::DailySync.new(@account, days: 2)
      sync.instance_variable_set(:@client, client)
      sync.sync_supplies
    end
  end

  def raw_order(wb_order_id)
    RawWb::Order.create!(
      account: @account, wb_order_id: wb_order_id, srid: "srid-#{wb_order_id}", delivery_type: "fbs",
      supplier_status: "complete", wb_status: "sorted", created_at: @closed_at - 2.hours
    )
  end

  def fulfillment_for(raw_order)
    order = Ec::Order.create!(platform: "wb", store: @store, order_key: "wb-ship-#{raw_order.wb_order_id}", order_status: "shipped")
    Ec::OrderFulfillment.create!(
      platform: "wb", store: @store, order: order,
      external_fulfillment_id: raw_order.wb_order_id.to_s, fulfillment_key: "wb:#{@store.id}:#{raw_order.wb_order_id}",
      fulfillment_type: "fbs", status: "shipped", raw_source_type: "RawWb::Order", raw_source_id: raw_order.id
    )
  end

  def supply_json(id, closed_at:, done: true)
    {
      "id" => id, "name" => "Shipment", "done" => done,
      "createdAt" => (@closed_at - 1.hour).iso8601, "closedAt" => closed_at&.iso8601, "scanDt" => nil
    }
  end
end
