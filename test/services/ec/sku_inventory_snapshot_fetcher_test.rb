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

    def initialize
      @posts = []
    end

    def post(path, body = {})
      @posts << { path: path, body: body }
      case path
      when "/v3/supply-order/list"
        { "order_ids" => [101], "last_id" => "" }
      when "/v3/supply-order/get"
        { "orders" => [{ "order_id" => 101, "supplies" => [{ "state" => "IN_TRANSIT", "bundle_id" => "bundle-101" }] }] }
      when "/v1/supply-order/bundle"
        { "items" => [{ "sku" => "390001", "quantity" => 7 }, { "sku" => "390999", "quantity" => 3 }] }
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

  test "ozon inbound uses live in transit supply order bundles" do
    fake_client = FakeOzonClient.new
    fetcher = Ec::SkuInventorySnapshotFetcher.new(ozon_client_factory: ->(_) { fake_client })

    result = fetcher.send(:ozon_inbound_quantities_by_sku_code, @ozon_account)

    assert_equal 7, result[@sku.sku_code]
    list_call = fake_client.posts.find { |call| call[:path] == "/v3/supply-order/list" }
    assert_equal ["IN_TRANSIT"], list_call[:body].dig(:filter, :states)
    assert fake_client.posts.any? { |call| call[:path] == "/v1/supply-order/bundle" }
  end
end
