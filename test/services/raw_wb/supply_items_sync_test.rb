require "test_helper"
require "securerandom"

class RawWbSupplyItemsSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :posts, :gets

    def initialize(supply_pages:, goods_pages:)
      @supply_pages = supply_pages
      @goods_pages = goods_pages
      @posts = []
      @gets = []
    end

    def post(service, path, body = {}, params = {})
      @posts << { service: service, path: path, body: body, params: params }
      @supply_pages.fetch(params.fetch(:offset))
    end

    def get(service, path, params = {})
      @gets << { service: service, path: path, params: params }
      @goods_pages.fetch([path, params.fetch(:offset)])
    end
  end

  setup do
    @token = SecureRandom.hex(6)
    @account = RawWb::SellerAccount.create!(
      name: "wb-supply-sync-#{@token}",
      api_token: "token-#{@token}",
      company_type: "small"
    )
    @base_id = 9_000_000_000 + @token.first(6).to_i(16) * 2_000
  end

  teardown do
    RawWb::SupplyItem.where(account_id: @account&.id).delete_all
    RawWb::Supply.where(account_id: @account&.id).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
  end

  test "paginates the complete supply list and every supply goods list" do
    first_supply_page = (1..1000).map { |offset| supply(@base_id + offset) }
    second_supply_page = [supply(@base_id + 1001)]
    first_goods_page = (1..1000).map { |nm_id| good(nm_id) }
    second_goods_page = [good(1001)]
    goods_pages = first_supply_page.each_with_object({}) do |item, pages|
      pages[[goods_path(item), 0]] = []
    end
    goods_pages[[goods_path(second_supply_page.first), 0]] = first_goods_page
    goods_pages[[goods_path(second_supply_page.first), 1000]] = second_goods_page
    client = FakeWbClient.new(
      supply_pages: { 0 => first_supply_page, 1000 => second_supply_page },
      goods_pages: goods_pages
    )
    sync = RawWb::DailySync.new(@account, days: 2)
    sync.instance_variable_set(:@client, client)
    sync.define_singleton_method(:sleep) { |_| }

    assert_equal 1001, sync.sync_supply_items
    assert_equal [0, 1000], client.posts.map { |request| request[:params][:offset] }
    assert_equal [0, 1000], client.gets.last(2).map { |request| request[:params][:offset] }
    assert_equal 1001, RawWb::Supply.count
    assert_equal 1001, RawWb::SupplyItem.where(
      account_id: @account.id,
      wb_supply_id: (@base_id + 1001).to_s
    ).count
  end

  test "clears stale goods only when an empty response succeeds" do
    RawWb::SupplyItem.create!(
      account: @account,
      wb_supply_id: @base_id.to_s,
      nm_id: 123,
      quantity: 8,
      accepted_qty: 1,
      synced_at: Time.current
    )
    item = supply(@base_id)
    client = FakeWbClient.new(
      supply_pages: { 0 => [item] },
      goods_pages: { [goods_path(item), 0] => [] }
    )
    sync = RawWb::DailySync.new(@account, days: 2)
    sync.instance_variable_set(:@client, client)
    sync.define_singleton_method(:sleep) { |_| }

    assert_equal 0, sync.sync_supply_items
    assert_not RawWb::SupplyItem.exists?(account_id: @account.id, wb_supply_id: @base_id.to_s)
  end

  test "removes goods stored under a preorder ID after WB assigns a supply ID" do
    item = supply(@base_id)
    preorder_id = item.fetch("preorderID").to_s
    RawWb::SupplyItem.create!(
      account: @account,
      wb_supply_id: preorder_id,
      nm_id: 123,
      quantity: 8,
      accepted_qty: 1,
      synced_at: 1.day.ago
    )
    client = FakeWbClient.new(
      supply_pages: { 0 => [item] },
      goods_pages: { [goods_path(item), 0] => [good(456)] }
    )
    sync = RawWb::DailySync.new(@account, days: 2)
    sync.instance_variable_set(:@client, client)
    sync.define_singleton_method(:sleep) { |_| }

    assert_equal 1, sync.sync_supply_items
    assert_not RawWb::SupplyItem.exists?(account_id: @account.id, wb_supply_id: preorder_id)
    assert RawWb::SupplyItem.exists?(
      account_id: @account.id,
      wb_supply_id: @base_id.to_s,
      nm_id: 456
    )
  end

  private

  def supply(id)
    {
      "supplyID" => id,
      "preorderID" => id + 10_000,
      "statusID" => 4,
      "boxTypeID" => 2,
      "createDate" => "2026-08-01T10:00:00+03:00"
    }
  end

  def good(nm_id)
    { "nmID" => nm_id, "quantity" => 10, "acceptedQuantity" => 3 }
  end

  def goods_path(item)
    "/api/v1/supplies/#{item.fetch("supplyID")}/goods"
  end
end
