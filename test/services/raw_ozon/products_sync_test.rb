require "test_helper"

class RawOzonProductsSyncTest < ActiveSupport::TestCase
  class FakeOzonClient
    def initialize(response)
      @response = response
    end

    def post(path, _body)
      raise "unexpected request: #{path}" unless path == "/v3/product/list" || path == "/v3/product/info/list"

      @response.fetch(path)
    end
  end

  test "marks missing and archived store products inactive after a successful catalog sync" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(client_id: "ozon-activity-#{token}", api_key: "token-#{token}", company_type: "general", raw_json: {})
    store = Ec::Store.create!(platform: "ozon", store_name: "ozon-activity-store-#{token}", company_type: "general", ozon_raw_account_id: account.id)
    sku = Ec::Sku.create!(sku_code: "OZON-ACTIVITY-#{token}", product_name: "Ozon activity")
    current = Ec::SkuProduct.create!(sku: sku, store: store, product_id: "88001", product_name: "Current")
    archived = Ec::SkuProduct.create!(sku: sku, store: store, product_id: "88003", product_name: "Archived")
    missing = Ec::SkuProduct.create!(sku: sku, store: store, product_id: "88002", product_name: "Missing")

    client = FakeOzonClient.new(
      "/v3/product/list" => { "result" => { "items" => [{ "product_id" => 88_001 }, { "product_id" => 88_003 }] } },
      "/v3/product/info/list" => {
        "items" => [
          { "id" => 88_001, "offer_id" => current.offer_id, "name" => "Current", "raw_json" => {} },
          { "id" => 88_003, "offer_id" => archived.offer_id, "name" => "Archived", "is_archived" => true }
        ]
      }
    )
    sync = RawOzon::WeeklySync.new(account, days: 7)
    sync.instance_variable_set(:@client, client)

    sync.sync_products

    assert current.reload.is_active
    assert_not archived.reload.is_active
    assert_not missing.reload.is_active
  ensure
    Ec::SkuProduct.where(id: [current&.id, archived&.id, missing&.id]).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all
    Ec::Store.where(id: store&.id).delete_all
    RawOzon::Product.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end
end
