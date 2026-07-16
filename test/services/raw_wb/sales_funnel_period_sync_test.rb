require "test_helper"
require "securerandom"

class RawWbSalesFunnelPeriodSyncTest < ActiveSupport::TestCase
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

  test "sync_period stores natural week sales funnel period rows" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-sales-funnel-period-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    client = FakeWbClient.new([
      response(order_count: 19, order_sum: 1262, open_count: 45),
      { "data" => { "products" => [], "currency" => "RUB" } },
    ])

    result = RawWb::SalesFunnelPeriodSync.new(account, client: client).sync_period(
      period_start: Date.new(2026, 7, 6),
      period_end: Date.new(2026, 7, 12)
    )

    assert_equal 1, result
    assert_equal :seller_analytics, client.requests.first[0]
    assert_equal "/api/analytics/v3/sales-funnel/products", client.requests.first[1]

    body = client.requests.first[2]
    assert_equal({ start: "2026-07-06", end: "2026-07-12" }, body[:selectedPeriod])
    assert_equal({ start: "2026-06-29", end: "2026-07-05" }, body[:pastPeriod])
    assert_equal [], body[:nmIds]
    assert_equal [], body[:brandNames]
    assert_equal [], body[:subjectIds]
    assert_equal [], body[:tagIds]
    assert_equal false, body[:skipDeletedNm]
    assert_equal({ field: "openCard", mode: "desc" }, body[:orderBy])
    assert_equal 1000, body[:limit]
    assert_equal 0, body[:offset]
    refute body.key?(:filter)
    refute body.key?(:page)

    row = RawWb::SalesFunnelPeriod.find_by!(account_id: account.id, period_start: Date.new(2026, 7, 6), period_end: Date.new(2026, 7, 12), nm_id: 268_913_787)
    assert_equal "WB-268", row.vendor_code
    assert_equal "Кроссовки для бега", row.product_name
    assert_equal "Demix", row.brand
    assert_equal 105, row.subject_id
    assert_equal "Кроссовки", row.subject
    assert_equal 45, row.open_card
    assert_equal 34, row.add_to_cart
    assert_equal 19, row.orders
    assert_equal 1262, row.orders_sum.to_i
    assert_equal 455, row.add_to_wishlist
    assert_equal 19, row.conv_to_cart.to_i
    assert_equal 65, row.cart_to_order.to_i
    assert_equal 19, row.wb_club_orders
    assert_equal 10, row.open_card_dynamic.to_i
    assert_equal "RUB", row.currency
    assert_equal "Обувь", row.tags.first["name"]
  ensure
    RawWb::SalesFunnelPeriod.where(account_id: account&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_period upserts the same account week and nm_id" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-sales-funnel-upsert-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    period_start = Date.new(2026, 7, 6)
    period_end = Date.new(2026, 7, 12)

    first_client = FakeWbClient.new([response(order_count: 1, order_sum: 100, open_count: 10), empty_response])
    RawWb::SalesFunnelPeriodSync.new(account, client: first_client).sync_period(period_start: period_start, period_end: period_end)

    second_client = FakeWbClient.new([response(order_count: 2, order_sum: 200, open_count: 20), empty_response])
    RawWb::SalesFunnelPeriodSync.new(account, client: second_client).sync_period(period_start: period_start, period_end: period_end)

    rows = RawWb::SalesFunnelPeriod.where(account_id: account.id, period_start: period_start, period_end: period_end, nm_id: 268_913_787)
    assert_equal 1, rows.count
    row = rows.first
    assert_equal 2, row.orders
    assert_equal 200, row.orders_sum.to_i
    assert_equal 20, row.open_card
  ensure
    RawWb::SalesFunnelPeriod.where(account_id: account&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "sync_period can request partial current week while storing natural week" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-sales-funnel-current-week-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    client = FakeWbClient.new([response(order_count: 1, order_sum: 100, open_count: 10), empty_response])

    RawWb::SalesFunnelPeriodSync.new(account, client: client).sync_period(
      period_start: Date.new(2026, 7, 13),
      period_end: Date.new(2026, 7, 19),
      selected_period_end: Date.new(2026, 7, 16)
    )

    body = client.requests.first[2]
    assert_equal({ start: "2026-07-13", end: "2026-07-16" }, body[:selectedPeriod])
    assert_equal({ start: "2026-07-06", end: "2026-07-09" }, body[:pastPeriod])

    row = RawWb::SalesFunnelPeriod.find_by!(account_id: account.id, nm_id: 268_913_787)
    assert_equal Date.new(2026, 7, 13), row.period_start
    assert_equal Date.new(2026, 7, 19), row.period_end
  ensure
    RawWb::SalesFunnelPeriod.where(account_id: account&.id).delete_all
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
              "past" => stat(order_count: 9, order_sum: 500, open_count: 40),
              "comparison" => {
                "openCountDynamic" => 10,
                "cartCountDynamic" => 30,
                "orderCountDynamic" => -100,
                "orderSumDynamic" => -100,
                "buyoutCountDynamic" => -100,
                "buyoutSumDynamic" => -100,
                "cancelCountDynamic" => 0,
                "cancelSumDynamic" => 0,
                "avgOrdersCountPerDayDynamic" => 0,
                "avgPriceDynamic" => -100,
                "shareOrderPercentDynamic" => -80,
                "addToWishlistDynamic" => 60,
                "timeToReadyDynamic" => { "days" => 1, "hours" => 8, "mins" => 34 },
                "localizationPercentDynamic" => 46,
                "wbClubDynamic" => {
                  "orderCount" => -100,
                  "orderSum" => -100,
                  "buyoutSum" => -100,
                  "buyoutCount" => -100,
                  "cancelSum" => 0,
                  "cancelCount" => 0,
                  "avgPrice" => -100,
                  "buyoutPercent" => 43,
                  "avgOrderCountPerDay" => 0.04,
                },
                "conversions" => {
                  "addToCartPercent" => 19,
                  "cartToOrderPercent" => 65,
                  "buyoutPercent" => 0,
                },
              },
            },
          },
        ],
      },
    }
  end

  def stat(order_count:, order_sum:, open_count:)
    {
      "period" => { "start" => "2026-07-06", "end" => "2026-07-12" },
      "openCount" => open_count,
      "cartCount" => 34,
      "orderCount" => order_count,
      "orderSum" => order_sum,
      "buyoutCount" => 19,
      "buyoutSum" => 1262,
      "cancelCount" => 0,
      "cancelSum" => 0,
      "avgPrice" => 1262,
      "avgOrdersCountPerDay" => 0.04,
      "shareOrderPercent" => 3,
      "addToWishlist" => 455,
      "timeToReady" => { "days" => 1, "hours" => 8, "mins" => 34 },
      "localizationPercent" => 46,
      "wbClub" => {
        "orderCount" => 19,
        "orderSum" => 1262,
        "buyoutSum" => 1262,
        "buyoutCount" => 19,
        "cancelSum" => 0,
        "cancelCount" => 0,
        "avgPrice" => 1262,
        "buyoutPercent" => 43,
        "avgOrderCountPerDay" => 0.04,
      },
      "conversions" => {
        "addToCartPercent" => 19,
        "cartToOrderPercent" => 65,
        "buyoutPercent" => 0,
      },
    }
  end
end
