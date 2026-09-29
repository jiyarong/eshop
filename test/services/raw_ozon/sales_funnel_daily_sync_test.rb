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
    client = FakeOzonClient.new([response(revenue: 336_000, ordered_units: 32), supplemental_response])

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
    assert_equal 0.42, row.conv_tocart_search.to_f
    assert_equal 0.61, row.conv_tocart_pdp.to_f
    assert_equal 28, row.delivered_units
    assert_equal 7.25, row.position_category.to_f
    assert_equal RawOzon::SalesFunnelDailySync::SUPPLEMENTAL_METRICS, client.requests.second[1][:metrics]
    assert_equal 7.25, row.raw_json.dig("metric_values", "position_category")
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

    RawOzon::SalesFunnelDailySync.new(account, client: FakeOzonClient.new([response(revenue: 100, ordered_units: 1), supplemental_response]), rate_limit_sleep: 0)
      .sync_date(stat_date)
    RawOzon::SalesFunnelDailySync.new(account, client: FakeOzonClient.new([response(revenue: 200, ordered_units: 2), supplemental_response]), rate_limit_sleep: 0)
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

  test "sync_range stores basic metrics when supplemental metrics are unavailable" do
    account = create_account("basic-only")
    client = FakeOzonClient.new([response(revenue: 500, ordered_units: 5), deprecated_metrics_error])

    result = RawOzon::SalesFunnelDailySync.new(account, client: client, rate_limit_sleep: 0)
      .sync_range(from_date: Date.new(2026, 7, 13), to_date: Date.new(2026, 7, 13))

    assert_equal false, result[:skipped]
    assert_equal 1, result[:ok]
    assert_equal false, result[:supplemental]
    assert_match "deprecated metrics", result[:supplemental_error]
    row = RawOzon::SalesFunnelDaily.find_by!(account_id: account.id, stat_date: Date.new(2026, 7, 13))
    assert_equal 42_403, row.hits_view
    assert_equal 5, row.ordered_units
    assert_nil row.delivered_units
    assert_nil row.position_category
    assert_nil row.conv_tocart_search
  ensure
    cleanup(account)
  end

  test "sync_range probes supplemental metrics only once per run after they are unavailable" do
    account = create_account("probe-once")
    client = FakeOzonClient.new([
      response(revenue: 100, ordered_units: 1), deprecated_metrics_error,
      response(revenue: 200, ordered_units: 2)
    ])

    result = RawOzon::SalesFunnelDailySync.new(account, client: client, rate_limit_sleep: 0)
      .sync_range(from_date: Date.new(2026, 7, 13), to_date: Date.new(2026, 7, 14))

    assert_equal 2, result[:ok]
    assert_equal [
      RawOzon::SalesFunnelDailySync::METRICS,
      RawOzon::SalesFunnelDailySync::SUPPLEMENTAL_METRICS,
      RawOzon::SalesFunnelDailySync::METRICS
    ], client.requests.map { |_, body| body[:metrics] }
  ensure
    cleanup(account)
  end

  test "a later run picks up supplemental metrics once the store gains access" do
    account = create_account("gains-access")
    date = Date.new(2026, 7, 13)
    RawOzon::SalesFunnelDailySync.new(account, client: FakeOzonClient.new([response(revenue: 100, ordered_units: 1), deprecated_metrics_error]), rate_limit_sleep: 0)
      .sync_range(from_date: date, to_date: date)

    result = RawOzon::SalesFunnelDailySync.new(account, client: FakeOzonClient.new([response(revenue: 100, ordered_units: 1), supplemental_response]), rate_limit_sleep: 0)
      .sync_range(from_date: date, to_date: date)

    assert_equal true, result[:supplemental]
    row = RawOzon::SalesFunnelDaily.find_by!(account_id: account.id, stat_date: date)
    assert_equal 28, row.delivered_units
    assert_equal 7.25, row.position_category.to_f
  ensure
    cleanup(account)
  end

  test "keeps stored supplemental values when a run cannot fetch them" do
    account = create_account("keep-supplemental")
    date = Date.new(2026, 7, 13)
    RawOzon::SalesFunnelDailySync.new(account, client: FakeOzonClient.new([response(revenue: 100, ordered_units: 1), supplemental_response]), rate_limit_sleep: 0)
      .sync_range(from_date: date, to_date: date)

    RawOzon::SalesFunnelDailySync.new(account, client: FakeOzonClient.new([response(revenue: 300, ordered_units: 3), deprecated_metrics_error]), rate_limit_sleep: 0)
      .sync_range(from_date: date, to_date: date)

    row = RawOzon::SalesFunnelDaily.find_by!(account_id: account.id, stat_date: date)
    assert_equal 3, row.ordered_units
    assert_equal 28, row.delivered_units
    assert_equal 7.25, row.position_category.to_f
  ensure
    cleanup(account)
  end

  test "a day with no basic rows is not mistaken for a skipped store" do
    account = create_account("empty-day")
    client = FakeOzonClient.new([empty_response, deprecated_metrics_error, response(revenue: 100, ordered_units: 1)])

    result = RawOzon::SalesFunnelDailySync.new(account, client: client, rate_limit_sleep: 0)
      .sync_range(from_date: Date.new(2026, 7, 13), to_date: Date.new(2026, 7, 14))

    assert_equal false, result[:skipped]
    assert_equal 1, result[:ok]
    assert_equal false, result[:supplemental]
  ensure
    cleanup(account)
  end

  test "transient errors on supplemental metrics still fail the run" do
    account = create_account("supplemental-transient")
    client = FakeOzonClient.new([
      response(revenue: 100, ordered_units: 1),
      RawOzon::OzonClient::RetryableError.new("429 rate-limited on /v1/analytics/data")
    ])

    assert_raises(RawOzon::OzonClient::RetryableError) do
      RawOzon::SalesFunnelDailySync.new(account, client: client, rate_limit_sleep: 0)
        .sync_range(from_date: Date.new(2026, 7, 13), to_date: Date.new(2026, 7, 13))
    end
  ensure
    cleanup(account)
  end

  private

  def create_account(label)
    token = SecureRandom.hex(6)
    RawOzon::SellerAccount.create!(client_id: "ozon-funnel-daily-#{label}-#{token}", api_key: "token-#{token}", company_type: "small")
  end

  def cleanup(account)
    RawOzon::SalesFunnelDaily.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  def deprecated_metrics_error
    RawOzon::OzonClient::ApiError.new('400 on /v1/analytics/data: {"code":3,"message":"deprecated metrics used"}')
  end

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

  def supplemental_response
    {
      "result" => {
        "data" => [{
          "dimensions" => [{ "id" => "3583393926", "name" => "Электрический полотенцесушитель" }],
          "metrics" => [0.42, 0.61, 28, 7.25],
        }],
        "totals" => [],
      },
      "timestamp" => "2026-07-16 06:56:02",
    }
  end
end
