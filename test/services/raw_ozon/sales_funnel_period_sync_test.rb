require "test_helper"
require "securerandom"

class RawOzonSalesFunnelPeriodSyncTest < ActiveSupport::TestCase
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

  test "sync_period stores natural week Ozon sales funnel rows" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-funnel-#{token}",
      api_key: "token-#{token}",
      company_type: "small"
    )
    client = FakeOzonClient.new([response(revenue: 336_000, ordered_units: 32), empty_response])

    result = RawOzon::SalesFunnelPeriodSync.new(account, client: client, rate_limit_sleep: 0).sync_period(
      period_start: Date.new(2026, 7, 6),
      period_end: Date.new(2026, 7, 12)
    )

    assert_equal({ ok: 1, fetched: 1, skipped: false }, result)
    assert_equal "/v1/analytics/data", client.requests.first[0]

    body = client.requests.first[1]
    assert_equal "2026-07-06", body[:date_from]
    assert_equal "2026-07-12", body[:date_to]
    assert_equal ["sku"], body[:dimension]
    assert_equal RawOzon::SalesFunnelPeriodSync::METRICS, body[:metrics]
    assert_equal [], body[:filters]
    assert_equal [{ key: "revenue", order: "DESC" }], body[:sort]
    assert_equal 1000, body[:limit]
    assert_equal 0, body[:offset]

    row = RawOzon::SalesFunnelPeriod.find_by!(account_id: account.id, period_start: Date.new(2026, 7, 6), period_end: Date.new(2026, 7, 12), sku: 3_583_393_926)
    assert_equal "Электрический полотенцесушитель", row.product_name
    assert_equal 42_403, row.hits_view
    assert_equal 22_611, row.hits_view_search
    assert_equal 1_548, row.hits_view_pdp
    assert_equal 27_280, row.session_view
    assert_equal 19_331, row.session_view_search
    assert_equal 868, row.session_view_pdp
    assert_equal 151, row.hits_tocart
    assert_equal 25, row.hits_tocart_search
    assert_equal 126, row.hits_tocart_pdp
    assert_equal 0.55, row.conv_tocart.to_f
    assert_equal 32, row.ordered_units
    assert_equal 336_000, row.revenue.to_i
    assert_equal 0, row.returns_count
    assert_equal 11, row.cancellations
  ensure
    RawOzon::SalesFunnelPeriod.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_period upserts same account week and sku" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-funnel-upsert-#{token}",
      api_key: "token-#{token}",
      company_type: "small"
    )
    period_start = Date.new(2026, 7, 6)
    period_end = Date.new(2026, 7, 12)

    RawOzon::SalesFunnelPeriodSync.new(account, client: FakeOzonClient.new([response(revenue: 100, ordered_units: 1), empty_response]), rate_limit_sleep: 0)
      .sync_period(period_start: period_start, period_end: period_end)
    RawOzon::SalesFunnelPeriodSync.new(account, client: FakeOzonClient.new([response(revenue: 200, ordered_units: 2), empty_response]), rate_limit_sleep: 0)
      .sync_period(period_start: period_start, period_end: period_end)

    rows = RawOzon::SalesFunnelPeriod.where(account_id: account.id, period_start: period_start, period_end: period_end, sku: 3_583_393_926)
    assert_equal 1, rows.count
    assert_equal 2, rows.first.ordered_units
    assert_equal 200, rows.first.revenue.to_i
  ensure
    RawOzon::SalesFunnelPeriod.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_period can request partial current week while storing natural week" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-funnel-current-#{token}",
      api_key: "token-#{token}",
      company_type: "small"
    )
    client = FakeOzonClient.new([response(revenue: 100, ordered_units: 1), empty_response])

    RawOzon::SalesFunnelPeriodSync.new(account, client: client, rate_limit_sleep: 0).sync_period(
      period_start: Date.new(2026, 7, 13),
      period_end: Date.new(2026, 7, 19),
      selected_period_end: Date.new(2026, 7, 16)
    )

    body = client.requests.first[1]
    assert_equal "2026-07-13", body[:date_from]
    assert_equal "2026-07-16", body[:date_to]

    row = RawOzon::SalesFunnelPeriod.find_by!(account_id: account.id, sku: 3_583_393_926)
    assert_equal Date.new(2026, 7, 13), row.period_start
    assert_equal Date.new(2026, 7, 19), row.period_end
  ensure
    RawOzon::SalesFunnelPeriod.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_period skips account period when premium metrics are unavailable" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-funnel-skip-#{token}",
      api_key: "token-#{token}",
      company_type: "small"
    )
    error = RawOzon::OzonClient::ApiError.new("403 on /v1/analytics/data: premium subscription required")

    result = RawOzon::SalesFunnelPeriodSync.new(account, client: FakeOzonClient.new([error]), rate_limit_sleep: 0).sync_period(
      period_start: Date.new(2026, 7, 6),
      period_end: Date.new(2026, 7, 12)
    )

    assert_equal 0, result[:ok]
    assert_equal 0, result[:fetched]
    assert_equal true, result[:skipped]
    assert_match "premium", result[:error]
    assert_equal 0, RawOzon::SalesFunnelPeriod.where(account_id: account.id).count
  ensure
    RawOzon::SalesFunnelPeriod.where(account_id: account&.id).delete_all
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
