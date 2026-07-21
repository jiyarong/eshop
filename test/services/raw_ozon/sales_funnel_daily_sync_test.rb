require "test_helper"
require "securerandom"

class RawOzonSalesFunnelDailySyncTest < ActiveSupport::TestCase
  class FakeOzonClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(path, body)
      @requests << [path, body]
      response = @responses.shift || empty_response
      raise response if response.is_a?(Exception)

      response
    end

    private

    def empty_response
      { "result" => { "data" => [], "totals" => [] }, "timestamp" => "2026-07-16 06:56:02" }
    end
  end

  test "sync_date stores daily Ozon sales funnel rows from single-day analytics request" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-funnel-daily-#{token}",
      api_key: "token-#{token}",
      company_type: "small"
    )
    client = FakeOzonClient.new([response(revenue: 336_000, ordered_units: 32), empty_response])

    result = RawOzon::SalesFunnelDailySync.new(account, client: client, rate_limit_sleep: 0)
      .sync_date(Date.new(2026, 7, 13))

    assert_equal 1, result
    assert_equal "/v1/analytics/data", client.requests.first[0]

    body = client.requests.first[1]
    assert_equal "2026-07-13", body[:date_from]
    assert_equal "2026-07-13", body[:date_to]
    assert_equal ["sku"], body[:dimension]
    assert_equal RawOzon::SalesFunnelDailySync::METRICS, body[:metrics]
    assert_equal [{ key: "revenue", order: "DESC" }], body[:sort]
    assert_equal 1000, body[:limit]
    assert_equal 0, body[:offset]

    row = RawOzon::SalesFunnelDaily.find_by!(account_id: account.id, stat_date: Date.new(2026, 7, 13), sku: 3_583_393_926)
    assert_equal "Электрический полотенцесушитель", row.product_name
    assert_equal 42_403, row.hits_view
    assert_equal 22_611, row.hits_view_search
    assert_equal 1_548, row.hits_view_pdp
    assert_equal 27_280, row.session_view
    assert_equal 151, row.hits_tocart
    assert_equal 32, row.ordered_units
    assert_equal 336_000, row.revenue.to_i
    assert_equal 11, row.cancellations
  ensure
    RawOzon::SalesFunnelDaily.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_date upserts same account date and sku" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-funnel-daily-upsert-#{token}",
      api_key: "token-#{token}",
      company_type: "small"
    )
    stat_date = Date.new(2026, 7, 13)

    RawOzon::SalesFunnelDailySync.new(account, client: FakeOzonClient.new([response(revenue: 100, ordered_units: 1), empty_response]), rate_limit_sleep: 0)
      .sync_date(stat_date)
    RawOzon::SalesFunnelDailySync.new(account, client: FakeOzonClient.new([response(revenue: 200, ordered_units: 2), empty_response]), rate_limit_sleep: 0)
      .sync_date(stat_date)

    rows = RawOzon::SalesFunnelDaily.where(account_id: account.id, stat_date: stat_date, sku: 3_583_393_926)
    assert_equal 1, rows.count
    assert_equal 2, rows.first.ordered_units
    assert_equal 200, rows.first.revenue.to_i
  ensure
    RawOzon::SalesFunnelDaily.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_range skips account range when premium metrics are unavailable" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-funnel-daily-skip-#{token}",
      api_key: "token-#{token}",
      company_type: "small"
    )
    error = RawOzon::OzonClient::ApiError.new("403 on /v1/analytics/data: premium subscription required")

    result = RawOzon::SalesFunnelDailySync.new(account, client: FakeOzonClient.new([error]), rate_limit_sleep: 0)
      .sync_range(from_date: Date.new(2026, 7, 13), to_date: Date.new(2026, 7, 13))

    assert_equal true, result[:skipped]
    assert_equal 0, result[:ok]
    assert_match "premium", result[:error]
    assert_equal 0, RawOzon::SalesFunnelDaily.where(account_id: account.id).count
  ensure
    RawOzon::SalesFunnelDaily.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  private

  def empty_response
    { "result" => { "data" => [], "totals" => [] }, "timestamp" => "2026-07-16 06:56:02" }
  end

  def response(revenue:, ordered_units:)
    {
      "result" => {
        "data" => [
          {
            "dimensions" => [
              {
                "id" => "3583393926",
                "name" => "Электрический полотенцесушитель",
              },
            ],
            "metrics" => [
              42_403,
              22_611,
              1_548,
              27_280,
              19_331,
              868,
              151,
              25,
              126,
              0.55,
              ordered_units,
              revenue,
              0,
              11,
            ],
          },
        ],
        "totals" => [],
      },
      "timestamp" => "2026-07-16 06:56:02",
    }
  end
end
