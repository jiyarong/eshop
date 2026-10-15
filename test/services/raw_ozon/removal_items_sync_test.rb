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
    assert_equal 1, RawOzon::RemovalItem.where(account: account).seller_received.sum(:quantity)
    assert_equal ["/v1/removal/from-stock/list", "/v1/removal/from-supply/list"] * 2,
      client.requests.map(&:first)
  ensure
    RawOzon::RemovalItem.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "re-reads back to the creation date of a request that is still open" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-removal-open-#{token}", api_key: "key-#{token}", company_type: "general", raw_json: {}
    )
    open_created_at = 200.days.ago.beginning_of_day
    finished_created_at = 300.days.ago.beginning_of_day
    insert_row(account, return_id: "OPEN-#{token}", state: "Передаём в логистику", box_id: "0",
      created_at: open_created_at)
    # An older request that already has a finished row must not widen the window.
    insert_row(account, return_id: "DONE-#{token}", state: "Завершено", box_id: "BOX-1", created_at: finished_created_at)
    insert_row(account, return_id: "DONE-#{token}", state: "Передаём в логистику", box_id: "0",
      created_at: finished_created_at)
    client = FakeOzonClient.new([])
    sync = RawOzon::DailySync.new(account, days: 2)
    sync.instance_variable_set(:@client, client)

    sync.sync_removal_items

    assert_equal open_created_at.to_date.iso8601, client.requests.first.last["date_from"]
    assert_operator client.requests.map { |_path, body| body["date_to"] }.last.to_date, :==, Date.current
  ensure
    RawOzon::RemovalItem.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "does not look further back than the cap for requests the platform never finishes" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-removal-cap-#{token}", api_key: "key-#{token}", company_type: "general", raw_json: {}
    )
    insert_row(account, return_id: "ANCIENT-#{token}", state: "Создаётся", box_id: "0",
      created_at: 500.days.ago.beginning_of_day)
    client = FakeOzonClient.new([])
    sync = RawOzon::DailySync.new(account, days: 2)
    sync.instance_variable_set(:@client, client)

    sync.sync_removal_items

    assert_equal (RawOzon::Syncs::RemovalItems::REMOVAL_WINDOW_DAYS - 1).days.ago.to_date.iso8601,
      client.requests.first.last["date_from"]
  ensure
    RawOzon::RemovalItem.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "drops the boxless placeholder row once the request reports its boxes" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-removal-box-#{token}", api_key: "key-#{token}", company_type: "general", raw_json: {}
    )
    placeholder = removal_row(return_id: "300", state: "Передаём в логистику", quantity: 1).merge("box_id" => 0)
    boxed = removal_row(return_id: "300", state: "Завершено", quantity: 1).merge("box_id" => "20228334774")
    other = removal_row(return_id: "400", state: "Создаётся", quantity: 2).merge("box_id" => 0)
    sync = RawOzon::DailySync.new(account, days: 2)

    sync.instance_variable_set(:@client, FakeOzonClient.new([
      { "returns_summary_report_rows" => [placeholder, other], "last_id" => "" }, {}
    ]))
    sync.sync_removal_items
    assert_equal 2, RawOzon::RemovalItem.where(account: account).count

    sync.instance_variable_set(:@client, FakeOzonClient.new([
      { "returns_summary_report_rows" => [boxed], "last_id" => "" }, {}
    ]))
    sync.sync_removal_items

    rows = RawOzon::RemovalItem.where(account: account).order(:return_id)
    assert_equal [["300", "20228334774"], ["400", "0"]], rows.map { |row| [row.return_id, row.box_id] }
    assert_equal 1, RawOzon::RemovalItem.where(account: account, return_id: "300").count
  ensure
    RawOzon::RemovalItem.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  private

  def insert_row(account, return_id:, state:, box_id:, created_at:)
    RawOzon::RemovalItem.create!(
      account: account, source_type: "stock", row_key: SecureRandom.hex(16), return_id: return_id, box_id: box_id,
      sku: "3902460130", offer_id: "OFFER-1", name: "Product", quantity: 1, quant_count: 0,
      stock_type: "Доступно к продаже", return_state: state, box_state: "", return_created_at: created_at,
      raw_json: {}, synced_at: Time.current
    )
  end

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
