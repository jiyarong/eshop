require "test_helper"

class RawWbSearchTermsSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(service, path, body)
      @requests << [service, path, body]
      @responses.shift || { "data" => { "items" => [], "currency" => "RUB" } }
    end
  end

  setup do
    @token = SecureRandom.hex(6)
    @account = RawWb::SellerAccount.create!(
      name: "wb-search-terms-#{@token}", api_token: "token-#{@token}", company_type: :small
    )
    @product = RawWb::Product.create!(
      account: @account, nm_id: 860_790_648, vendor_code: "SEARCH-#{@token}"
    )
  end

  teardown do
    RawWb::AnalyticsSearchTerm.where(account_id: @account&.id).delete_all
    RawWb::Product.where(account_id: @account&.id).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
  end

  test "stores a complete natural-week response with its exact period and raw item" do
    client = FakeWbClient.new([response([search_item])])

    result = sync(client).sync_period(period_start: Date.new(2026, 8, 3), period_end: Date.new(2026, 8, 9))

    assert_equal 1, result[:ok]
    assert_equal 5, client.requests.size
    service, path, body = client.requests.first
    assert_equal :seller_analytics, service
    assert_equal "/api/v2/search-report/product/search-texts", path
    assert_equal({ start: "2026-08-03", end: "2026-08-09" }, body[:currentPeriod])
    assert_equal 30, body[:limit]
    assert_equal "openCard", body[:topOrderBy]
    assert_not body.key?(:offset)

    row = RawWb::AnalyticsSearchTerm.find_by!(account_id: @account.id, keyword: "полотенцесушитель")
    assert_equal Date.new(2026, 8, 3), row.period_from
    assert_equal Date.new(2026, 8, 9), row.period_to
    assert_equal 860_790_648, row.nm_id
    assert_equal 34, row.avg_position.to_i
    assert_equal 30, row.median_position.to_i
    assert_equal 5, row.frequency
    assert_equal 140, row.week_frequency
    assert_equal 1, row.orders
    assert_equal 100, row.orders_percentile
    assert_equal "RUB", row.currency
    assert_equal true, row.is_card_rated
    assert_equal ["openCard"], row.raw_json["topDimensions"]
    assert_equal search_item, row.raw_json.except("topDimensions")
    assert row.synced_at.present?
  end

  test "replaces a completed week's rows when top search terms change" do
    first_client = FakeWbClient.new([response([search_item])])
    sync(first_client).sync_period(period_start: Date.new(2026, 8, 3), period_end: Date.new(2026, 8, 9))

    replacement = search_item.merge("text" => "полотенцесушитель белый", "orders" => { "current" => 2, "percentile" => 90 })
    second_client = FakeWbClient.new([response([replacement])])
    sync(second_client).sync_period(period_start: Date.new(2026, 8, 3), period_end: Date.new(2026, 8, 9))

    rows = RawWb::AnalyticsSearchTerm.where(account_id: @account.id)
    assert_equal 1, rows.count
    assert_equal "полотенцесушитель белый", rows.sole.keyword
    assert_equal 2, rows.sole.orders
  end

  test "rejects a range that is not a complete natural week" do
    error = assert_raises(ArgumentError) do
      sync(FakeWbClient.new([])).sync_period(
        period_start: Date.new(2026, 8, 1), period_end: Date.new(2026, 8, 9)
      )
    end

    assert_equal "period must be a complete Monday-Sunday week", error.message
  end

  test "does not paginate when WB returns more items than the requested limit" do
    oversized_items = 31.times.map do |index|
      search_item.merge("text" => "полотенцесушитель #{index}")
    end
    client = FakeWbClient.new([response(oversized_items)])

    result = sync(client).sync_period(period_start: Date.new(2026, 8, 3), period_end: Date.new(2026, 8, 9))

    assert_equal 31, result[:ok]
    assert_equal 5, client.requests.size
    assert_equal 31, RawWb::AnalyticsSearchTerm.where(account_id: @account.id).count
  end

  test "merges the same keyword returned by multiple top dimensions" do
    client = FakeWbClient.new([
      response([search_item]),
      response([search_item.merge("addToCart" => { "current" => 6, "percentile" => 70 })])
    ])

    result = sync(client).sync_period(period_start: Date.new(2026, 8, 3), period_end: Date.new(2026, 8, 9))

    assert_equal 1, result[:ok]
    row = RawWb::AnalyticsSearchTerm.find_by!(account_id: @account.id, keyword: "полотенцесушитель")
    assert_equal 6, row.add_to_cart
    assert_equal %w[openCard addToCart], row.raw_json["topDimensions"]
  end

  private

  def sync(client)
    RawWb::SearchTermsSync.new(@account, client: client, rate_limit_sleep: 0)
  end

  def response(items)
    { "data" => { "items" => items, "currency" => "RUB" } }
  end

  def search_item
    {
      "text" => "полотенцесушитель",
      "nmId" => 860_790_648,
      "subjectName" => "Полотенцесушители",
      "brandName" => "Brand",
      "vendorCode" => "SEARCH-#{@token}",
      "name" => "Полотенцесушитель электрический",
      "isCardRated" => true,
      "rating" => 6,
      "feedbackRating" => 4.8,
      "price" => { "minPrice" => 150, "maxPrice" => 300 },
      "frequency" => { "current" => 5 },
      "weekFrequency" => 140,
      "medianPosition" => { "current" => 30 },
      "avgPosition" => { "current" => 34 },
      "openCard" => { "current" => 5, "percentile" => 50 },
      "addToCart" => { "current" => 4, "percentile" => 60 },
      "openToCart" => { "current" => 80, "percentile" => 70 },
      "orders" => { "current" => 1, "percentile" => 100 },
      "cartToOrder" => { "current" => 25, "percentile" => 80 },
      "visibility" => { "current" => 20 }
    }
  end
end
