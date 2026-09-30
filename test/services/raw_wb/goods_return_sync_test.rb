require "test_helper"
require "securerandom"

class RawWbGoodsReturnSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def get(service, path, params = {})
      @requests << { service:, path:, params: }
      @responses.fetch([params.fetch(:status), params.fetch(:offset)], {})
    end
  end

  setup do
    @token = SecureRandom.hex(6)
    @account = RawWb::SellerAccount.create!(
      name: "wb-goods-return-sync-#{@token}",
      api_token: "token-#{@token}",
      company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "wb",
      store_name: "WB goods return sync #{@token}",
      company_type: "small",
      wb_raw_account_id: @account.id
    )
    @base_id = 90_000_000_000 + @token.first(6).to_i(16) * 10
  end

  teardown do
    return_ids = Ec::Return.where(store_id: @store&.id).pluck(:id)
    Ec::ReturnSourceLink.where(return_id: return_ids).delete_all
    Ec::ReturnItem.where(return_id: return_ids).delete_all
    Ec::Return.where(id: return_ids).delete_all
    RawWb::GoodsReturn.where(account_id: @account&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
  end

  test "syncs active and archive returns into the existing table" do
    active_item = item(@base_id, return_status: "Готов к выдаче")
    archived_item = active_item.merge(
      "returnStatus" => "Выдано",
      "completedDt" => "2026-09-28 11:30:00"
    )
    second_archived_item = item(@base_id + 1, return_status: "Истек срок хранения на пвз")
    client = FakeWbClient.new(
      ["active", 0] => { "count" => 1, "report" => [active_item] },
      ["archive", 0] => { "count" => 2, "report" => [archived_item, second_archived_item] }
    )
    sync = build_sync(client)

    result = sync.sync_goods_return

    assert_equal({ ok: 2, fetched: 2, created: 2, updated: 0 }, result)
    assert_equal %w[active archive], client.requests.map { |request| request.dig(:params, :status) }
    assert client.requests.all? { |request| request[:path] == "/api/analytics/v1/item-returns" }
    assert client.requests.all? { |request| request.dig(:params, :limit) == 1000 }

    archived = RawWb::GoodsReturn.find_by!(account: @account, shk_id: @base_id)
    assert_equal "2051935008379", archived.barcode
    assert_equal "Выдано", archived.status
    assert_equal 0, archived.is_status_active
    assert_equal Time.zone.parse("2026-09-28 11:30:00"), archived.completed_dt
    assert Ec::ReturnItem.joins(:return).find_by!(ec_returns: { store_id: @store.id }, item_key: @base_id.to_s).restockable?

    active_requests = client.requests.select { |request| request.dig(:params, :status) == "active" }
    assert_equal [0], active_requests.map { |request| request.dig(:params, :offset) }
  end

  test "paginates each status using count and offset" do
    first_page = Array.new(1000) { |index| item(@base_id + index, return_status: "Готов к выдаче") }
    last_item = item(@base_id + 1000, return_status: "В пути в пвз")
    client = FakeWbClient.new(
      ["active", 0] => { "count" => 1001, "report" => first_page },
      ["active", 1000] => { "count" => 1001, "report" => [last_item] }
    )
    sync = build_sync(client)

    rows = sync.send(
      :fetch_goods_return_status,
      Date.new(2026, 9, 1),
      Date.new(2026, 9, 29),
      status: "active"
    )

    assert_equal 1001, rows.size
    assert_equal [0, 1000], client.requests.map { |request| request.dig(:params, :offset) }
  end

  test "treats an empty response as no returns" do
    client = FakeWbClient.new({})
    sync = build_sync(client)

    result = sync.sync_goods_return

    assert_equal({ ok: 0, fetched: 0, created: 0, updated: 0 }, result)
    assert_equal %w[active archive], client.requests.map { |request| request.dig(:params, :status) }
  end

  private

  def build_sync(client)
    RawWb::DailySync.new(@account, days: 1).tap do |sync|
      sync.instance_variable_set(:@client, client)
      sync.define_singleton_method(:sleep) { |_| }
    end
  end

  def item(shk_id, return_status:)
    {
      "sku" => "2051935008379",
      "brand" => "ZEPPTO",
      "completedDt" => nil,
      "dstOfficeAddress" => "Minsk",
      "dstOfficeId" => 172_968,
      "expiredDt" => nil,
      "kiz" => nil,
      "nmId" => 1_113_652_534,
      "orderDt" => "2026-09-20",
      "orderId" => 5_532_849_951,
      "readyToReturnDt" => "2026-09-25 12:06:14",
      "returnType" => "Возврат товара, который приехал по МП, продавцу",
      "shkId" => shk_id,
      "srid" => "mp.#{@token}.r",
      "returnStatus" => return_status,
      "stickerId" => shk_id.to_s,
      "subjectName" => "Test item",
      "techSize" => "0"
    }
  end
end
