require "test_helper"
require "securerandom"

class Ec::SkuInventoryOverviewTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "INV-SVC-#{@token}", product_name: "库存服务测试")

    @wb_account = RawWb::SellerAccount.create!(
      name: "wb-svc-#{@token}",
      api_token: "token-#{@token}",
      company_type: "small"
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "ozon-svc-#{@token}",
      client_id: "client-#{@token}",
      api_key: "key-#{@token}",
      company_type: "small"
    )

    @wb_store = Ec::Store.create!(
      platform: "wb",
      store_name: "WB 库存服务店 #{@token}",
      company_type: "small",
      wb_raw_account_id: @wb_account.id,
      is_active: true
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon",
      store_name: "Ozon 库存服务店 #{@token}",
      company_type: "small",
      ozon_raw_account_id: @ozon_account.id,
      is_active: true
    )

    Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @wb_store,
      product_id: "123456",
      platform_sku_id: "WB-CHRT-#{@token}"
    )
    Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @ozon_store,
      product_id: "OZON-PROD-#{@token}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@token}"
    )

    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "NORMAL-#{@token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 30,
      received_quantity: 30,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "ADJUST-#{@token}",
      status: "closed",
      batch_type: :wb_fbw_offset,
      purchased_quantity: 0,
      received_quantity: -4,
      defect_offset_note: "WB FBW correction",
      purchase_unit_price_cny: 1
    )

    wb_fbw_order = Ec::Order.create!(
      platform: "wb",
      store: @wb_store,
      external_order_id: "WB-FBW-#{@token}",
      external_order_number: "WB-FBW-#{@token}",
      order_key: "wb:#{@wb_store.id}:WB-FBW-#{@token}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-10 10:00:00"),
      synced_at: Time.zone.parse("2026-06-10 10:05:00")
    )
    wb_fbw_fulfillment = wb_fbw_order.fulfillments.create!(
      platform: "wb",
      store: @wb_store,
      external_fulfillment_id: "WB-FBW-F-#{@token}",
      fulfillment_key: "wb:#{@wb_store.id}:WB-FBW-F-#{@token}",
      fulfillment_type: "fbw",
      status: "delivered"
    )
    wb_fbw_order.items.create!(
      fulfillment: wb_fbw_fulfillment,
      platform: "wb",
      store: @wb_store,
      external_item_id: "WB-FBW-I-#{@token}",
      platform_sku_id: "123456",
      offer_id: "WB-OFFER-#{@token}",
      product_name_source: "WB FBW 商品",
      quantity: 5,
      unit_price: 50,
      payout: 200,
      commission_amount: 20,
      discount_amount: 0,
      currency_code: "BYN"
    )

    wb_fbs_order = Ec::Order.create!(
      platform: "wb",
      store: @wb_store,
      external_order_id: "WB-FBS-#{@token}",
      external_order_number: "WB-FBS-#{@token}",
      order_key: "wb:#{@wb_store.id}:WB-FBS-#{@token}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-11 10:00:00"),
      synced_at: Time.zone.parse("2026-06-11 10:05:00")
    )
    wb_fbs_fulfillment = wb_fbs_order.fulfillments.create!(
      platform: "wb",
      store: @wb_store,
      external_fulfillment_id: "WB-FBS-F-#{@token}",
      fulfillment_key: "wb:#{@wb_store.id}:WB-FBS-F-#{@token}",
      fulfillment_type: "fbs",
      status: "delivered"
    )
    wb_fbs_order.items.create!(
      fulfillment: wb_fbs_fulfillment,
      platform: "wb",
      store: @wb_store,
      external_item_id: "WB-FBS-I-#{@token}",
      platform_sku_id: "123456",
      offer_id: "WB-OFFER-#{@token}",
      product_name_source: "WB FBS 商品",
      quantity: 7,
      unit_price: 50,
      payout: 280,
      commission_amount: 20,
      discount_amount: 0,
      currency_code: "BYN"
    )

    ozon_order = Ec::Order.create!(
      platform: "ozon",
      store: @ozon_store,
      external_order_id: "OZON-#{@token}",
      external_order_number: "OZON-#{@token}",
      order_key: "ozon:#{@ozon_store.id}:OZON-#{@token}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-12 10:00:00"),
      synced_at: Time.zone.parse("2026-06-12 10:05:00")
    )
    ozon_order.items.create!(
      platform: "ozon",
      store: @ozon_store,
      external_item_id: "OZON-I-#{@token}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@token}",
      product_name_source: "Ozon 商品",
      quantity: 9,
      unit_price: 100,
      payout: 900,
      commission_amount: 20,
      discount_amount: 0,
      currency_code: "BYN"
    )

    RawWb::GoodsReturn.create!(
      account: @wb_account,
      shk_id: 20_000_000 + @token.to_i(16),
      nm_id: 123_456,
      barcode: "WB-RETURN-#{@token}",
      status: "ready_to_return",
      synced_at: Time.zone.parse("2026-06-13 10:00:00")
    )
    RawOzon::Return.create!(
      account: @ozon_account,
      return_id: 30_000_000 + @token.to_i(16),
      return_schema: "FBO",
      return_type: "Return",
      posting_number: "OZON-#{@token}",
      order_number: "OZON-#{@token}",
      ozon_sku: 3_902_460_130,
      offer_id: "OFFER-#{@token}",
      product_name: "Ozon 商品",
      quantity: 2,
      raw_json: {},
      synced_at: Time.zone.parse("2026-06-14 10:00:00")
    )

    RawWb::SupplyItem.create!(
      account: @wb_account,
      wb_supply_id: "WB-SUPPLY-#{@token}",
      nm_id: 123_456,
      accepted_qty: 100,
      synced_at: Time.zone.parse("2026-06-15 10:00:00")
    )
    RawOzon::SupplyOrder.create!(
      account: @ozon_account,
      supply_order_id: "OZON-SUPPLY-#{@token}",
      status: "COMPLETED",
      items: { "3902460130" => 100 },
      raw_json: {},
      synced_at: Time.zone.parse("2026-06-15 10:00:00")
    )

    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "wb",
      account_id: @wb_account.id,
      store: @wb_store,
      store_name: @wb_store.store_name,
      fulfillment_type: "fbw",
      quantity: 4,
      is_latest: true,
      synced_at: Time.zone.parse("2026-06-16 10:00:00"),
      metadata: {}
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      account_id: @ozon_account.id,
      store: @ozon_store,
      store_name: @ozon_store.store_name,
      fulfillment_type: "fbo",
      quantity: 6,
      is_latest: true,
      synced_at: Time.zone.parse("2026-06-16 10:05:00"),
      metadata: {}
    )
  end

  teardown do
    Ec::SkuInventoryLevel.where(sku_code: @sku.sku_code).delete_all
    RawOzon::SupplyOrder.where(account_id: @ozon_account.id).delete_all
    RawWb::SupplyItem.where(account_id: @wb_account.id).delete_all
    RawOzon::Return.where(account_id: @ozon_account.id).delete_all
    RawWb::GoodsReturn.where(account_id: @wb_account.id).delete_all
    Ec::OrderItem.joins(:order).where(ec_orders: { store_id: [@wb_store.id, @ozon_store.id] }).delete_all
    Ec::OrderFulfillment.where(store_id: [@wb_store.id, @ozon_store.id]).delete_all
    Ec::Order.where(store_id: [@wb_store.id, @ozon_store.id]).delete_all
    Ec::SkuBatch.where(sku_code: @sku.sku_code).delete_all
    Ec::SkuProduct.where(sku_code: @sku.sku_code).delete_all
    Ec::Store.where(id: [@wb_store.id, @ozon_store.id]).delete_all
    RawWb::SellerAccount.where(id: @wb_account.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "summarizes purchase adjustment sales returns and ignores supply quantities in stock formulas" do
    overview = Ec::SkuInventoryOverview.new(@sku).call
    summary = overview[:summary]

    assert_equal 30, summary[:purchase_quantity]
    assert_equal(-4, summary[:adjustment_quantity])
    assert_equal 26, summary[:received_quantity]
    assert_equal 21, summary[:sales_quantity]
    assert_equal 3, summary[:return_quantity]
    assert_equal 200, summary[:supply_quantity]
    assert_equal 10, summary[:platform_stock]
    assert_equal 8, summary[:book_stock]
    assert_equal(-2, summary[:available_stock])

    wb_row = overview[:store_rows].find { |row| row[:platform] == "wb" }
    ozon_row = overview[:store_rows].find { |row| row[:platform] == "ozon" }

    assert_equal 12, wb_row[:sales_quantity]
    assert_equal 1, wb_row[:return_quantity]
    assert_equal 100, wb_row[:supply_quantity]

    assert_equal 9, ozon_row[:sales_quantity]
    assert_equal 2, ozon_row[:return_quantity]
    assert_equal 100, ozon_row[:supply_quantity]
  end

  test "captures order status quantity buckets per store" do
    wb_processing_order = Ec::Order.create!(
      platform: "wb",
      store: @wb_store,
      external_order_id: "WB-PROC-#{@token}",
      external_order_number: "WB-PROC-#{@token}",
      order_key: "wb:#{@wb_store.id}:WB-PROC-#{@token}",
      order_status: "processing",
      ordered_at: Time.zone.parse("2026-06-17 10:00:00"),
      synced_at: Time.zone.parse("2026-06-17 10:05:00")
    )
    wb_processing_order.items.create!(
      platform: "wb",
      store: @wb_store,
      external_item_id: "WB-PROC-I-#{@token}",
      platform_sku_id: "123456",
      offer_id: "WB-OFFER-#{@token}",
      product_name_source: "WB processing 商品",
      quantity: 3,
      unit_price: 50,
      payout: 120,
      commission_amount: 10,
      discount_amount: 0,
      currency_code: "BYN"
    )

    ozon_shipped_order = Ec::Order.create!(
      platform: "ozon",
      store: @ozon_store,
      external_order_id: "OZON-SHIP-#{@token}",
      external_order_number: "OZON-SHIP-#{@token}",
      order_key: "ozon:#{@ozon_store.id}:OZON-SHIP-#{@token}",
      order_status: "shipped",
      ordered_at: Time.zone.parse("2026-06-18 10:00:00"),
      synced_at: Time.zone.parse("2026-06-18 10:05:00")
    )
    ozon_shipped_order.items.create!(
      platform: "ozon",
      store: @ozon_store,
      external_item_id: "OZON-SHIP-I-#{@token}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@token}",
      product_name_source: "Ozon shipped 商品",
      quantity: 4,
      unit_price: 100,
      payout: 400,
      commission_amount: 20,
      discount_amount: 0,
      currency_code: "BYN"
    )

    overview = Ec::SkuInventoryOverview.new(@sku).call

    wb_row = overview[:store_rows].find { |row| row[:platform] == "wb" }
    ozon_row = overview[:store_rows].find { |row| row[:platform] == "ozon" }

    assert_equal(
      {
        "pending" => 0,
        "processing" => 3,
        "shipping" => 0,
        "signed" => 12
      },
      wb_row[:order_status_counts]
    )
    assert_equal(
      {
        "pending" => 0,
        "processing" => 0,
        "shipping" => 4,
        "signed" => 9
      },
      ozon_row[:order_status_counts]
    )
  end
end
