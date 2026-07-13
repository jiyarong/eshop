require "test_helper"

class Ec::PlatformInboundInventoryQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "INBOUND-#{@token}", product_name: "送仓中测试")
    @wb_account = RawWb::SellerAccount.create!(name: "wb-inbound-#{@token}", api_token: "token-#{@token}", company_type: "small")
    @ozon_account = RawOzon::SellerAccount.create!(company_name: "ozon-inbound-#{@token}", client_id: "client-#{@token}", api_key: "key-#{@token}", company_type: "small")
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "WB Inbound #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id, is_active: true)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon Inbound #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id, is_active: true)
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "123#{@token.hex % 10_000}", platform_sku_id: "WB-CHRT-#{@token}")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZON-PROD-#{@token}", platform_sku_id: "390#{@token.hex % 10_000}", offer_id: "OFFER-#{@token}")
  end

  teardown do
    RawOzon::SupplyOrder.where(account_id: @ozon_account&.id).delete_all
    RawWb::SupplyItem.where(account_id: @wb_account&.id).delete_all
    RawWb::Supply.where(account_id: @wb_account&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id].compact).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "wb counts active supply quantities not yet accepted" do
    nm_id = @sku.sku_products.find_by!(platform: "wb").product_id.to_i
    active_supply = RawWb::Supply.create!(account: @wb_account, wb_supply_id: "WB-INBOUND-#{@token}", preorder_id: 10_000 + @token.hex % 10_000, status_id: 2, synced_at: Time.current)
    created_supply = RawWb::Supply.create!(account: @wb_account, wb_supply_id: "WB-CREATED-#{@token}", preorder_id: 20_000 + @token.hex % 10_000, status_id: 1, synced_at: Time.current)
    completed_supply = RawWb::Supply.create!(account: @wb_account, wb_supply_id: "WB-DONE-#{@token}", preorder_id: 30_000 + @token.hex % 10_000, status_id: 5, synced_at: Time.current)

    RawWb::SupplyItem.create!(account: @wb_account, wb_supply_id: active_supply.wb_supply_id, nm_id: nm_id, quantity: 12, accepted_qty: 3, synced_at: Time.current)
    RawWb::SupplyItem.create!(account: @wb_account, wb_supply_id: created_supply.wb_supply_id, nm_id: nm_id, quantity: 50, accepted_qty: 0, synced_at: Time.current)
    RawWb::SupplyItem.create!(account: @wb_account, wb_supply_id: completed_supply.wb_supply_id, nm_id: nm_id, quantity: 20, accepted_qty: 20, synced_at: Time.current)

    result = Ec::PlatformInboundInventoryQuery.new(platform: "wb", account: @wb_account).by_sku_code

    assert_equal 9, result[@sku.sku_code]
  end

  test "ozon counts only in transit supply order items" do
    ozon_sku = @sku.sku_products.find_by!(platform: "ozon").platform_sku_id
    RawOzon::SupplyOrder.create!(account: @ozon_account, supply_order_id: "OZON-IN-#{@token}", status: "IN_TRANSIT", items: { ozon_sku => 7 }, raw_json: {}, synced_at: Time.current)
    RawOzon::SupplyOrder.create!(account: @ozon_account, supply_order_id: "OZON-READY-#{@token}", status: "READY_TO_SUPPLY", items: { ozon_sku => 40 }, raw_json: {}, synced_at: Time.current)
    RawOzon::SupplyOrder.create!(account: @ozon_account, supply_order_id: "OZON-DONE-#{@token}", status: "COMPLETED", items: { ozon_sku => 12 }, raw_json: {}, synced_at: Time.current)

    result = Ec::PlatformInboundInventoryQuery.new(platform: "ozon", account: @ozon_account).by_sku_code

    assert_equal 7, result[@sku.sku_code]
  end
end
