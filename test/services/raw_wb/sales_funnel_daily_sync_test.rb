require "test_helper"
require "securerandom"

class RawWbSalesFunnelDailySyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(service, path, body)
      @requests << [service, path, body]
      @responses.shift || { "data" => { "products" => [], "currency" => "RUB" } }
    end
  end

  test "sync_date stores daily sales funnel rows from single-day products request" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-sales-funnel-daily-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    client = FakeWbClient.new([response(order_count: 19, order_sum: 1262, open_count: 45), empty_response])

    result = RawWb::SalesFunnelDailySync.new(account, client: client, rate_limit_sleep: 0)
      .sync_date(Date.new(2026, 7, 13))

    assert_equal 1, result
    assert_equal :seller_analytics, client.requests.first[0]
    assert_equal "/api/analytics/v3/sales-funnel/products", client.requests.first[1]

    body = client.requests.first[2]
    assert_equal({ start: "2026-07-13", end: "2026-07-13" }, body[:selectedPeriod])
    assert_equal({ start: "2026-07-06", end: "2026-07-06" }, body[:pastPeriod])
    assert_equal [], body[:nmIds]
    assert_equal({ field: "openCard", mode: "desc" }, body[:orderBy])
    assert_equal 1000, body[:limit]
    assert_equal 0, body[:offset]

    row = RawWb::SalesFunnelDaily.find_by!(account_id: account.id, stat_date: Date.new(2026, 7, 13), nm_id: 268_913_787)
    assert_equal "WB-268", row.vendor_code
    assert_equal "Кроссовки для бега", row.product_name
    assert_equal 45, row.open_card
    assert_equal 34, row.add_to_cart
    assert_equal 19, row.orders
    assert_equal 1262, row.orders_sum.to_i
    assert_equal 455, row.add_to_wishlist
    assert_equal 19, row.conv_to_cart.to_i
    assert_equal "RUB", row.currency
  ensure
    RawWb::SalesFunnelDaily.where(account_id: account&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_date upserts same account date and nm_id" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-sales-funnel-daily-upsert-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    stat_date = Date.new(2026, 7, 13)

    RawWb::SalesFunnelDailySync.new(account, client: FakeWbClient.new([response(order_count: 1, order_sum: 100, open_count: 10), empty_response]), rate_limit_sleep: 0)
      .sync_date(stat_date)
    RawWb::SalesFunnelDailySync.new(account, client: FakeWbClient.new([response(order_count: 2, order_sum: 200, open_count: 20), empty_response]), rate_limit_sleep: 0)
      .sync_date(stat_date)

    rows = RawWb::SalesFunnelDaily.where(account_id: account.id, stat_date: stat_date, nm_id: 268_913_787)
    assert_equal 1, rows.count
    assert_equal 2, rows.first.orders
    assert_equal 200, rows.first.orders_sum.to_i
    assert_equal 20, rows.first.open_card
  ensure
    RawWb::SalesFunnelDaily.where(account_id: account&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  private

  def empty_response
    { "data" => { "products" => [], "currency" => "RUB" } }
  end

  def response(order_count:, order_sum:, open_count:)
    {
      "data" => {
        "currency" => "RUB",
        "products" => [
          {
            "product" => {
              "nmId" => 268_913_787,
              "title" => "Кроссовки для бега",
              "vendorCode" => "WB-268",
              "brandName" => "Demix",
              "subjectId" => 105,
              "subjectName" => "Кроссовки",
              "tags" => [{ "id" => 1, "name" => "Обувь" }],
              "productRating" => 4.5,
              "feedbackRating" => 4,
              "stocks" => { "wb" => 3, "mp" => 4, "balanceSum" => 700 },
            },
            "statistic" => {
              "selected" => stat(order_count: order_count, order_sum: order_sum, open_count: open_count),
            },
          },
        ],
      },
    }
  end

  def stat(order_count:, order_sum:, open_count:)
    {
      "openCount" => open_count,
      "cartCount" => 34,
      "orderCount" => order_count,
      "orderSum" => order_sum,
      "buyoutCount" => 19,
      "buyoutSum" => 1262,
      "cancelCount" => 0,
      "cancelSum" => 0,
      "avgPrice" => 100,
      "avgOrdersCountPerDay" => 3,
      "shareOrderPercent" => 12,
      "addToWishlist" => 455,
      "timeToReady" => { "days" => 1, "hours" => 2, "mins" => 3 },
      "localizationPercent" => 88,
      "conversions" => {
        "addToCartPercent" => 19,
        "cartToOrderPercent" => 65,
        "buyoutPercent" => 35,
      },
    }
  end
end
