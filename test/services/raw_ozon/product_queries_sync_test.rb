require "test_helper"

class RawOzonProductQueriesSyncTest < ActiveSupport::TestCase
  class FakeOzonClient
    attr_reader :requests

    def initialize(fail_from: nil)
      @requests = []
      @fail_from = fail_from
    end

    def post(path, body)
      @requests << [path, body]
      if @fail_from && body.fetch(:date_from).start_with?(@fail_from)
        raise RawOzon::OzonClient::ApiError, "403 premium period unavailable"
      end

      sku = body.fetch(:skus).first.to_i
      period = body.fetch(:date_from).start_with?("2026-07-27") ? 1 : 2

      if path.end_with?("/details")
        query = {
          "sku" => sku, "query" => "query-#{period}", "query_index" => 1,
          "currency" => "RUB", "unique_search_users" => 80 * period,
          "unique_view_users" => 20 * period, "position" => 7.5,
          "view_conversion" => 25, "order_count" => period, "gmv" => 900 * period
        }
        {
          "queries" => [query.merge("query_index" => 2), query],
          "page_count" => 1
        }
      else
        item = {
          "sku" => sku, "offer_id" => "OFFER-1", "name" => "Product",
          "category" => "Category", "currency" => "RUB",
          "unique_search_users" => 100 * period, "unique_view_users" => 25 * period,
          "position" => 8.5, "view_conversion" => 25, "gmv" => 1_200 * period
        }
        {
          "items" => [item, item.dup],
          "page_count" => 1
        }
      end
    end
  end

  test "continues with newer weeks when an older premium period is unavailable" do
    travel_to Time.utc(2026, 8, 17, 8) do
      token = SecureRandom.hex(6)
      account = RawOzon::SellerAccount.create!(
        client_id: "ozon-queries-skip-#{token}", api_key: "token-#{token}",
        company_type: "general", raw_json: {}
      )
      product = RawOzon::Product.create!(
        account:, ozon_product_id: 223_456, offer_id: "OFFER-2", name: "Product",
        raw_json: { "sku" => 887_654 }
      )
      sync = RawOzon::WeeklySync.new(account, days: 15)
      sync.instance_variable_set(:@client, FakeOzonClient.new(fail_from: "2026-07-27"))
      sync.define_singleton_method(:sleep) { |_| }

      result = sync.sync_product_queries

      assert_equal 1, result[:weeks]
      assert_equal 1, result[:summaries]
      assert_equal 1, result[:details]
      assert_equal Date.new(2026, 7, 27), result[:failed_weeks].sole[:period_from]
      assert_equal [Date.new(2026, 8, 3)], RawOzon::ProductQuery.where(account:).pluck(:period_from)
    ensure
      RawOzon::ProductQueryDetail.where(account_id: account&.id).delete_all
      RawOzon::ProductQuery.where(account_id: account&.id).delete_all
      RawOzon::Product.where(id: product&.id).delete_all
      RawOzon::SellerAccount.where(id: account&.id).delete_all
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
      invalid_product = RawOzon::Product.create!(
        account:, ozon_product_id: 123_457, offer_id: "INVALID", name: "Invalid product",
        raw_json: { "sku" => 0 }
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

      assert_equal({ ok: 4, summaries: 2, details: 2, weeks: 2, failed_weeks: [] }, result)
      assert_equal [Date.new(2026, 7, 27), Date.new(2026, 8, 3)],
        RawOzon::ProductQuery.where(account:).order(:period_from).pluck(:period_from)
      assert_not RawOzon::ProductQueryDetail.exists?(account:, query: "stale-query")
      assert_equal %w[query-1 query-2],
        RawOzon::ProductQueryDetail.where(account:).order(:period_from).pluck(:query)

      client.requests.each do |_path, body|
        assert_equal ["987654"], body.fetch(:skus)
        assert_match(/T00:00:00Z\z/, body.fetch(:date_from))
        assert_match(/T23:59:59Z\z/, body.fetch(:date_to))
      end
      detail_requests = client.requests.select { |path, _body| path.end_with?("/details") }
      summary_requests = client.requests.reject { |path, _body| path.end_with?("/details") }
      assert_equal [1000, 1000], summary_requests.map { |_path, body| body.fetch(:page_size) }
      assert_equal [100, 100], detail_requests.map { |_path, body| body.fetch(:page_size) }
      assert_equal [15, 15], detail_requests.map { |_path, body| body.fetch(:limit_by_sku) }
    ensure
      RawOzon::ProductQueryDetail.where(account_id: account&.id).delete_all
      RawOzon::ProductQuery.where(account_id: account&.id).delete_all
      RawOzon::Product.where(id: [product&.id, invalid_product&.id]).delete_all
      RawOzon::SellerAccount.where(id: account&.id).delete_all
    end
  end
end
