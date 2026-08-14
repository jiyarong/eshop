require "test_helper"

class RawWbSearchReportSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(service, path, body)
      @requests << [service, path, body]
      @responses.shift || { "data" => { "groups" => [], "currency" => "RUB" } }
    end
  end

  setup do
    @token = SecureRandom.hex(6)
    @account = RawWb::SellerAccount.create!(
      name: "wb-search-report-#{@token}", api_token: "token-#{@token}", company_type: :small
    )
    @product = RawWb::Product.create!(account: @account, nm_id: 860_790_648, vendor_code: "SEARCH-#{@token}")
  end

  teardown do
    RawWb::SearchReportProduct.where(account_id: @account&.id).delete_all
    RawWb::Product.where(account_id: @account&.id).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
  end

  test "stores product-level search report metrics for a complete natural week" do
    item = search_report_item
    client = FakeWbClient.new([response([item])])

    result = sync(client).sync_period(period_start: Date.new(2026, 8, 3), period_end: Date.new(2026, 8, 9))

    assert_equal 1, result[:ok]
    service, path, body = client.requests.sole
    assert_equal :seller_analytics, service
    assert_equal "/api/v2/search-report/report", path
    assert_equal({ start: "2026-08-03", end: "2026-08-09" }, body[:currentPeriod])
    assert_equal({ start: "2026-07-27", end: "2026-08-02" }, body[:pastPeriod])
    assert_equal [860_790_648], body[:nmIds]
    assert_equal "openCard", body.dig(:orderBy, :field)

    row = RawWb::SearchReportProduct.find_by!(account_id: @account.id, nm_id: 860_790_648)
    assert_equal 33, row.avg_position.to_i
    assert_equal(-10, row.avg_position_dynamics.to_i)
    assert_equal 62, row.open_card
    assert_equal 8, row.add_to_cart
    assert_equal 13, row.open_to_cart.to_i
    assert_equal 1, row.orders
    assert_equal 13, row.cart_to_order.to_i
    assert_equal 50, row.visibility.to_i
    assert_equal "BYN", row.currency
    assert_equal item, row.raw_json.except("_report", "_groupMetrics")
    assert_equal "BYN", row.raw_json.dig("_report", "currency")
  end

  test "replaces a completed week atomically on refresh" do
    sync(FakeWbClient.new([response([search_report_item])])).sync_period(
      period_start: Date.new(2026, 8, 3), period_end: Date.new(2026, 8, 9)
    )
    replacement = search_report_item.deep_merge("avgPosition" => { "current" => 21, "dynamics" => 12 })

    sync(FakeWbClient.new([response([replacement])])).sync_period(
      period_start: Date.new(2026, 8, 3), period_end: Date.new(2026, 8, 9)
    )

    rows = RawWb::SearchReportProduct.where(account_id: @account.id)
    assert_equal 1, rows.count
    assert_equal 21, rows.sole.avg_position.to_i
  end

  test "rejects a period that is not a complete natural week" do
    error = assert_raises(ArgumentError) do
      sync(FakeWbClient.new([])).sync_period(
        period_start: Date.new(2026, 8, 4), period_end: Date.new(2026, 8, 9)
      )
    end

    assert_equal "period must be a complete Monday-Sunday week", error.message
  end

  private

  def sync(client)
    RawWb::SearchReportSync.new(@account, client:, rate_limit_sleep: 0)
  end

  def response(items)
    { "data" => { "groups" => [{ "items" => items }], "currency" => "BYN" } }
  end

  def search_report_item
    {
      "nmId" => 860_790_648,
      "vendorCode" => "SEARCH-#{@token}",
      "name" => "Полотенцесушитель",
      "subjectName" => "Полотенцесушители",
      "brandName" => "ZEPPTO",
      "mainPhoto" => "https://example.com/1.webp",
      "isAdvertised" => true,
      "isSubstitutedSKU" => false,
      "isCardRated" => true,
      "rating" => 10,
      "feedbackRating" => 4.9,
      "price" => { "minPrice" => 467, "maxPrice" => 467 },
      "avgPosition" => { "current" => 33, "dynamics" => -10 },
      "openCard" => { "current" => 62, "dynamics" => -77 },
      "addToCart" => { "current" => 8, "dynamics" => -76 },
      "openToCart" => { "current" => 13, "dynamics" => 8 },
      "orders" => { "current" => 1, "dynamics" => -86 },
      "cartToOrder" => { "current" => 13, "dynamics" => -38 },
      "visibility" => { "current" => 50, "dynamics" => -21 }
    }
  end
end
