require "test_helper"

class Ec::SkuInventorySnapshotFetcherTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :posts, :gets

    def initialize(supplies:, goods_by_supply_id:)
      @supplies = supplies
      @goods_by_supply_id = goods_by_supply_id
      @posts = []
      @gets = []
    end

    def post(service, path, body = {})
      @posts << { service: service, path: path, body: body }
      return @supplies if service == :supplies && path == "/api/v1/supplies"

      raise "unexpected WB POST #{service} #{path}"
    end

    def get(service, path, params = {})
      @gets << { service: service, path: path, params: params }
      supply_id = path.split("/")[4]
      @goods_by_supply_id.fetch(supply_id, [])
    end
  end

  class FakeOzonClient
    attr_reader :posts

    def initialize(product_id:, ozon_sku:)
      @posts = []
      @product_id = product_id
      @ozon_sku = ozon_sku
    end

    def post(path, body = {})
      @posts << { path: path, body: body }
      case path
      when "/v4/product/info/stocks"
        {
          "items" => [
            {
              "product_id" => @product_id,
              "stocks" => [
                { "type" => "fbo", "present" => 45 },
                { "type" => "fbs", "present" => 4 }
              ]
            }
          ],
          "cursor" => ""
        }
      when "/v2/analytics/stock_on_warehouses"
        {
          "result" => {
            "rows" => [
              {
                "sku" => @ozon_sku,
                "warehouse_name" => "Екатеринбург_РФЦ_НОВЫЙ",
                "item_code" => "OFFER-TEST",
                "free_to_sell_amount" => 0,
                "promised_amount" => 10,
                "reserved_amount" => 0
              },
              {
                "sku" => @ozon_sku,
                "warehouse_name" => "Казань_РФЦ_НОВЫЙ",
                "item_code" => "OFFER-TEST",
                "free_to_sell_amount" => 45,
                "promised_amount" => 0,
                "reserved_amount" => 0
              }
            ]
          }
        }
      else
        raise "unexpected Ozon POST #{path}"
      end
    end
  end

  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "FETCH-IN-#{@token}", product_name: "实时在途测试")
    @wb_account = RawWb::SellerAccount.create!(name: "wb-fetch-#{@token}", api_token: "token-#{@token}", company_type: "small")
    @ozon_account = RawOzon::SellerAccount.create!(company_name: "ozon-fetch-#{@token}", client_id: "client-#{@token}", api_key: "key-#{@token}", company_type: "small")
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "WB Fetch #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id, is_active: true)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon Fetch #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id, is_active: true)
    @wb_product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "1144249749", platform_sku_id: "WB-CHRT-#{@token}")
    @ozon_product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZON-PROD-#{@token}", platform_sku_id: "390001", offer_id: "OFFER-#{@token}")
  end

  teardown do
    RawWb::SupplyItem.where(account_id: @wb_account&.id).delete_all
    RawWb::Supply.where(account_id: @wb_account&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id].compact).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "wb inbound uses live 2 3 4 supplies instead of stale raw supply rows" do
    RawWb::Supply.create!(
      account: @wb_account,
      wb_supply_id: "STALE-#{@token}",
      preorder_id: 100_000 + @token.hex % 10_000,
      status_id: 3,
      synced_at: 1.month.ago
    )
    RawWb::SupplyItem.create!(
      account: @wb_account,
      wb_supply_id: "STALE-#{@token}",
      nm_id: @wb_product.product_id.to_i,
      quantity: 46,
      accepted_qty: 0,
      synced_at: 1.month.ago
    )

    fake_client = FakeWbClient.new(
      supplies: [{ "supplyID" => 40295360, "preorderID" => 52251864, "statusID" => 2 }],
      goods_by_supply_id: {
        "40295360" => [
          { "nmID" => @wb_product.product_id.to_i, "quantity" => 12, "acceptedQuantity" => 5 },
          { "nmID" => 999, "quantity" => 20, "acceptedQuantity" => 0 }
        ]
      }
    )
    fetcher = Ec::SkuInventorySnapshotFetcher.new(wb_client_factory: ->(_) { fake_client })

    result = fetcher.send(:wb_inbound_quantities_by_sku_code, @wb_account)

    assert_equal 7, result[@sku.sku_code]
    assert_equal [2, 3, 4], fake_client.posts.first[:body][:statusIDs]
    assert_equal "/api/v1/supplies/40295360/goods", fake_client.gets.first[:path]
  end

  test "ozon inbound uses promised warehouse stock amount" do
    fake_client = FakeOzonClient.new(product_id: @ozon_product.product_id.to_i, ozon_sku: @ozon_product.platform_sku_id.to_i)
    fetcher = Ec::SkuInventorySnapshotFetcher.new(ozon_client_factory: ->(_) { fake_client })

    rows = fetcher.send(:ozon_rows, Time.zone.parse("2026-07-13 10:00:00"))

    inbound = rows.find { |row| row[:sku_code] == @sku.sku_code && row[:fulfillment_type] == "inbound" }
    fbs = rows.find { |row| row[:sku_code] == @sku.sku_code && row[:fulfillment_type] == "fbs" }
    assert_equal 10, inbound[:quantity]
    assert_equal 0, fbs[:quantity]
    assert_equal "ozon_analytics_stock_on_warehouses.promised_amount", inbound[:metadata][:inbound_source]
    assert fake_client.posts.any? { |call| call[:path] == "/v2/analytics/stock_on_warehouses" }
    assert_not fake_client.posts.any? { |call| call[:path] == "/v3/supply-order/list" }
  end
end
