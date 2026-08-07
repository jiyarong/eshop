require "test_helper"

class RawOzonRemovalItemsSyncTest < ActiveSupport::TestCase
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

  test "syncs stock and supply removal rows idempotently" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-removal-#{token}", api_key: "key-#{token}", company_type: "general", raw_json: {}
    )
    stock_row = removal_row(return_id: "100", state: "Собирается на складе", quantity: 1)
    supply_row = removal_row(return_id: "200", state: "Завершено", quantity: 1)
    client = FakeOzonClient.new([
      { "returns_summary_report_rows" => [stock_row, stock_row], "last_id" => "" },
      { "returns_summary_report_rows" => [supply_row], "last_id" => "" },
      { "returns_summary_report_rows" => [stock_row, stock_row, stock_row], "last_id" => "" },
      { "returns_summary_report_rows" => [supply_row], "last_id" => "" }
    ])
    sync = RawOzon::DailySync.new(account, days: 2)
    sync.instance_variable_set(:@client, client)

    assert_equal 3, sync.sync_removal_items
    assert_operator Date.iso8601(client.requests.first.last["date_from"]), :<=, 89.days.ago.to_date
    assert_equal 4, sync.sync_removal_items
    assert_equal 2, RawOzon::RemovalItem.where(account: account).count
    assert_equal 3, RawOzon::RemovalItem.find_by!(account: account, return_id: "100").quantity
    assert_equal 3, RawOzon::RemovalItem.find_by!(account: account, return_id: "100").raw_json["_source_row_count"]
    assert_equal 3, RawOzon::RemovalItem.where(account: account).deducting_return_inventory.sum(:quantity)
    assert_equal ["/v1/removal/from-stock/list", "/v1/removal/from-supply/list"] * 2,
      client.requests.map(&:first)
  ensure
    RawOzon::RemovalItem.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  private

  def removal_row(return_id:, state:, quantity:)
    {
      "name" => "Product",
      "offer_id" => "OFFER-1",
      "sku" => "3902460130",
      "quantity_for_return" => quantity,
      "box_id" => "BOX-#{return_id}",
      "return_id" => return_id,
      "stock_type" => "Доступно к продаже",
      "return_state" => state,
      "box_state" => state == "Завершено" ? "Получена" : ""
    }
  end
end
