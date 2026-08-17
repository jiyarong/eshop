require "test_helper"

class RawOzonProductQueriesSyncTest < ActiveSupport::TestCase
  class FakeOzonClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def post(path, body)
      @requests << [path, body]
      sku = body.fetch(:skus).first.to_i
      period = body.fetch(:date_from).start_with?("2026-07-27") ? 1 : 2

      if path.end_with?("/details")
        {
          "queries" => [{
            "sku" => sku, "query" => "query-#{period}", "query_index" => 1,
            "currency" => "RUB", "unique_search_users" => 80 * period,
            "unique_view_users" => 20 * period, "position" => 7.5,
            "view_conversion" => 25, "order_count" => period, "gmv" => 900 * period
          }],
          "page_count" => 1
        }
      else
        {
          "items" => [{
            "sku" => sku, "offer_id" => "OFFER-1", "name" => "Product",
            "category" => "Category", "currency" => "RUB",
            "unique_search_users" => 100 * period, "unique_view_users" => 25 * period,
            "position" => 8.5, "view_conversion" => 25, "gmv" => 1_200 * period
          }],
          "page_count" => 1
        }
      end
    end
  end

  test "syncs every completed week with an inclusive Sunday and replaces stale rows" do
    travel_to Time.utc(2026, 8, 17, 8) do
      token = SecureRandom.hex(6)
      account = RawOzon::SellerAccount.create!(
        client_id: "ozon-queries-#{token}", api_key: "token-#{token}",
        company_type: "general", raw_json: {}
      )
      product = RawOzon::Product.create!(
        account:, ozon_product_id: 123_456, offer_id: "OFFER-1", name: "Product",
        raw_json: { "sku" => 987_654 }
      )
      RawOzon::ProductQueryDetail.create!(
        account:, period_from: Date.new(2026, 8, 3), period_to: Date.new(2026, 8, 9),
        sku: 987_654, query: "stale-query", synced_at: 1.day.ago
      )
      client = FakeOzonClient.new
      sync = RawOzon::WeeklySync.new(account, days: 15)
      sync.instance_variable_set(:@client, client)
      sync.define_singleton_method(:sleep) { |_| }

      result = sync.sync_product_queries

      assert_equal({ ok: 4, summaries: 2, details: 2, weeks: 2 }, result)
      assert_equal [Date.new(2026, 7, 27), Date.new(2026, 8, 3)],
        RawOzon::ProductQuery.where(account:).order(:period_from).pluck(:period_from)
      assert_not RawOzon::ProductQueryDetail.exists?(account:, query: "stale-query")
      assert_equal %w[query-1 query-2],
        RawOzon::ProductQueryDetail.where(account:).order(:period_from).pluck(:query)

      client.requests.each do |_path, body|
        assert_match(/T00:00:00Z\z/, body.fetch(:date_from))
        assert_match(/T23:59:59Z\z/, body.fetch(:date_to))
        assert_equal 1000, body.fetch(:page_size)
      end
      detail_requests = client.requests.select { |path, _body| path.end_with?("/details") }
      assert_equal [15, 15], detail_requests.map { |_path, body| body.fetch(:limit_by_sku) }
    ensure
      RawOzon::ProductQueryDetail.where(account_id: account&.id).delete_all
      RawOzon::ProductQuery.where(account_id: account&.id).delete_all
      RawOzon::Product.where(id: product&.id).delete_all
      RawOzon::SellerAccount.where(id: account&.id).delete_all
    end
  end
end
