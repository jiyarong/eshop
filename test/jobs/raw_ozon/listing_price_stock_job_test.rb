require "test_helper"

module RawOzon
  class ListingPriceStockJobTest < ActiveJob::TestCase
    class FakeClient
      attr_reader :calls

      def initialize
        @calls = []
      end

      def import_pictures(**kwargs)
        @calls << [:pictures, kwargs]
        { "task_id" => "pic-1" }
      end

      def import_prices(items)
        @calls << [:prices, items]
        { "result" => "ok" }
      end

      def update_stocks(stocks)
        @calls << [:stocks, stocks]
        { "result" => "ok" }
      end
    end

    setup do
      token = SecureRandom.hex(4).upcase
      @sku = Ec::Sku.create!(sku_code: "PRICE-STOCK-#{token}", product_name: "Price stock")
      @account = RawOzon::SellerAccount.create!(client_id: "price-stock-#{token}", api_key: "secret", company_type: "general")
      @store = Ec::Store.create!(platform: "ozon", store_name: "Price stock #{token}", company_type: "general", ozon_raw_account_id: @account.id)
      payload = {
        "price" => { "price" => "10", "old_price" => "12", "min_price" => "9", "currency_code" => "RUB" },
        "images" => ["https://cdn.example.test/a.jpg"],
        "primary_image" => "https://cdn.example.test/a.jpg",
        "stock" => { "warehouse_id" => 55, "stock" => 3, "quant_size" => 1 }
      }
      @publication = Ec::OzonListingPublication.create!(
        account: @account, store: @store, sku_code: @sku.sku_code, operation: "import", offer_id: @sku.sku_code,
        payload: payload, payload_checksum: Ec::OzonListingPublication.checksum_for(payload), product_id: "123", state: "ready_for_price_stock"
      )
    end

    teardown do
      Ec::OzonListingPublication.where(id: @publication&.id).delete_all
      Ec::Sku.where(id: @sku&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      RawOzon::SellerAccount.where(id: @account&.id).delete_all
    end

    test "updates pictures, price and stock after import" do
      fake = FakeClient.new
      singleton = RawOzon::ListingClient.singleton_class
      original = RawOzon::ListingClient.method(:for_account)
      singleton.define_method(:for_account) { |_account| fake }
      RawOzon::ListingPriceStockJob.perform_now(@publication.id)

      @publication.reload
      assert_equal "completed", @publication.state
      assert_equal %i[pictures prices stocks], fake.calls.map(&:first)
      assert_equal "123", fake.calls.dig(1, 1, 0, :product_id)
      assert_equal "123", fake.calls.dig(2, 1, 0, "product_id")
    ensure
      singleton.define_method(:for_account, original)
    end
  end
end
