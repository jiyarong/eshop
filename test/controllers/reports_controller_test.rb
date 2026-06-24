require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @sku_code = "TST-#{SecureRandom.hex(4).upcase}"
    @current_user = create_user_with_roles("reports-#{@sku_code.downcase}@example.com", "manager")
    sign_in @current_user
    @sku = Ec::Sku.create!(
      sku_code: @sku_code,
      product_name: "测试商品",
      product_name_ru: "Тестовый товар",
      is_active: true
    )
    @second_sku_code = "TST2-#{@sku_code.delete_prefix("TST-")}"
    @second_sku = Ec::Sku.create!(
      sku_code: @second_sku_code,
      product_name: "第二个测试商品",
      product_name_ru: "Второй тестовый товар",
      is_active: true
    )
    @sales_ozon_account = RawOzon::SellerAccount.create!(
      client_id: "reports-ozon-#{@sku_code}",
      api_key: "test-key",
      company_name: "销量统计 Ozon Raw #{@sku_code}",
      company_type: "general"
    )
    @sales_store = Ec::Store.create!(
      platform: "ozon",
      store_name: "销量统计 Ozon 店 #{@sku_code}",
      company_type: "general",
      ozon_raw_account_id: @sales_ozon_account.id
    )
    @sales_wb_account = RawWb::SellerAccount.create!(
      name: "销量统计 WB Raw #{@sku_code}",
      api_token: "test-token",
      company_type: "small"
    )
    @wb_sales_store = Ec::Store.create!(
      platform: "wb",
      store_name: "销量统计 WB 店 #{@sku_code}",
      company_type: "small",
      wb_raw_account_id: @sales_wb_account.id
    )

    RawOzon::Product.create!(
      account: @sales_ozon_account,
      ozon_product_id: 9_876_543_210,
      offer_id: "OFFER-#{@sku_code}",
      name: "Ozon 绑定商品",
      raw_json: { "sku" => 3_902_460_130 },
      synced_at: Time.zone.parse("2026-06-01 09:00:00")
    )

    @inventory_snapshot = Ec::InventorySnapshot.create!(
      sku_code: @sku.sku_code,
      platform: "wb",
      account_id: 2,
      store_name: "TaxiLink",
      stock: 7,
      supply: 3,
      sold: 5,
      fbs: 1,
      synced_at: Time.zone.parse("2026-05-30 10:00")
    )

    @inventory_ozon_snapshot = Ec::InventorySnapshot.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      account_id: 1,
      store_name: "Nevastal",
      stock: 4,
      supply: 6,
      sold: 2,
      fbs: 3,
      synced_at: Time.zone.parse("2026-05-30 11:00")
    )

    @inventory_total = Ec::InventoryTotal.create!(
      sku_code: @sku.sku_code,
      total_supply: 9,
      total_stock: 11,
      total_sold: 7,
      total_fbs: 4,
      total_received: 20,
      synced_at: Time.zone.parse("2026-05-30 10:00")
    )

    @second_inventory_snapshot = Ec::InventorySnapshot.create!(
      sku_code: @second_sku.sku_code,
      platform: "wb",
      account_id: 3,
      store_name: "WorldChoice",
      stock: 99,
      supply: 100,
      sold: 1,
      fbs: 0,
      synced_at: Time.zone.parse("2026-05-30 10:00")
    )

    @second_inventory_total = Ec::InventoryTotal.create!(
      sku_code: @second_sku.sku_code,
      total_supply: 100,
      total_stock: 99,
      total_sold: 1,
      total_fbs: 0,
      total_received: 100,
      synced_at: Time.zone.parse("2026-05-30 10:00")
    )

    @sku_cost = Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      purchase_price_cny: 10,
      freight_to_by_cny: 2,
      customs_misc_cny: 1,
      customs_duty_rate: 0.1,
      import_vat_rate: 0.2,
      pkg_length_cm: 10,
      pkg_width_cm: 20,
      pkg_height_cm: 30,
      misc_cost_cny: 0.5,
      damage_rate: 0.03
    )

    @wb_cost = Ec::SkuPlatformCost.create!(
      sku_code: @sku.sku_code,
      platform: "wb",
      delivery_mode: "fbo",
      company_type: "small",
      exchange_rate_rub_cny: 10,
      acquiring_rate: 0.02,
      ad_spend_rate: 0.08,
      commission_rate: 0.12,
      target_price_rub: 1000,
      wb_logistics_base_rub: 60,
      logistics_coeff: 1.2,
      fbo_delivery_cny: 5,
      wb_return_rate: 0.2,
      wb_fixed_return_rate: 0.1,
      storage_30d_cny: 1,
      sales_tax_rate: 0.06
    )

    @ozon_cost = Ec::SkuPlatformCost.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      delivery_mode: "fbs",
      company_type: "general",
      exchange_rate_rub_cny: 10,
      acquiring_rate: 0.02,
      ad_spend_rate: 0.08,
      commission_rate: 0.12,
      target_price_rf_rub: 1200,
      target_price_by_rub: 1300,
      ozon_fwd_base_rub: 80,
      ozon_fwd_per_liter_rub: 12,
      ozon_ret_base_rub: 70,
      ozon_ret_per_liter_rub: 10,
      ozon_warehouse_op_rub: 20,
      ozon_fbs_delivery_rub: 30
    )

    @sales_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "SALE-#{@sku_code}",
      external_order_number: "SALE-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:SALE-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-01 10:00:00"),
      synced_at: Time.zone.parse("2026-06-01 10:10:00")
    )
    @sales_fulfillment = @sales_order.fulfillments.create!(
      platform: "ozon",
      store: @sales_store,
      external_fulfillment_id: "SALE-F-#{@sku_code}",
      fulfillment_key: "ozon:#{@sales_store.id}:SALE-F-#{@sku_code}",
      fulfillment_type: "fbo",
      status: "delivered"
    )
    @sales_order.items.create!(
      fulfillment: @sales_fulfillment,
      platform: "ozon",
      store: @sales_store,
      external_item_id: "SALE-I-#{@sku_code}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@sku_code}",
      product_name_source: "销量统计测试商品",
      quantity: 2,
      unit_price: 100,
      payout: 160,
      commission_amount: 20,
      discount_amount: 10,
      currency_code: "BYN"
    )

    @return_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "RETURN-#{@sku_code}",
      external_order_number: "RETURN-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:RETURN-#{@sku_code}",
      order_status: "returned",
      ordered_at: Time.zone.parse("2026-06-01 15:00:00"),
      synced_at: Time.zone.parse("2026-06-01 15:10:00")
    )
    @return_fulfillment = @return_order.fulfillments.create!(
      platform: "ozon",
      store: @sales_store,
      external_fulfillment_id: "RETURN-F-#{@sku_code}",
      fulfillment_key: "ozon:#{@sales_store.id}:RETURN-F-#{@sku_code}",
      fulfillment_type: "fbs",
      status: "returned"
    )
    @return_order.items.create!(
      fulfillment: @return_fulfillment,
      platform: "ozon",
      store: @sales_store,
      external_item_id: "RETURN-I-#{@sku_code}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@sku_code}",
      product_name_source: "销量统计测试商品",
      quantity: 1,
      unit_price: 100,
      payout: 80,
      commission_amount: 10,
      discount_amount: 5,
      currency_code: "BYN"
    )

    @wb_sales_order = Ec::Order.create!(
      platform: "wb",
      store: @wb_sales_store,
      external_order_id: "WB-SALE-#{@sku_code}",
      external_order_number: "WB-SALE-#{@sku_code}",
      order_key: "wb:#{@wb_sales_store.id}:WB-SALE-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-08 11:00:00"),
      synced_at: Time.zone.parse("2026-06-08 11:10:00")
    )
    @wb_sales_order.items.create!(
      platform: "wb",
      store: @wb_sales_store,
      external_item_id: "WB-SALE-I-#{@sku_code}",
      platform_sku_id: "123456",
      offer_id: "WB-OFFER-#{@sku_code}",
      product_name_source: "销量统计 WB 测试商品",
      quantity: 3,
      unit_price: 50,
      payout: 120,
      commission_amount: 15,
      discount_amount: 6,
      currency_code: "BYN"
    )

    Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @sales_store,
      product_id: "9876543210",
      offer_id: "OFFER-#{@sku_code}",
      platform_sku_id: "3902460130",
      product_name: "Ozon 绑定商品"
    )
    Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @wb_sales_store,
      product_id: "123456",
      offer_id: "WB-OFFER-#{@sku_code}",
      product_name: "WB 绑定商品"
    )

    @second_sku_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "SECOND-SALE-#{@sku_code}",
      external_order_number: "SECOND-SALE-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:SECOND-SALE-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-08 08:00:00"),
      synced_at: Time.zone.parse("2026-06-08 08:10:00")
    )
    @second_sku_order.items.create!(
      platform: "ozon",
      store: @sales_store,
      external_item_id: "SECOND-SALE-I-#{@sku_code}",
      platform_sku_id: "OZON-SKU-#{@second_sku_code}",
      offer_id: @second_sku.sku_code,
      sku_code: @second_sku.sku_code,
      product_name_source: "第二个销量统计测试商品",
      quantity: 4,
      unit_price: 25,
      payout: 90,
      commission_amount: 8,
      discount_amount: 4,
      currency_code: "BYN"
    )
    RawOzon::Product.create!(
      account: @sales_ozon_account,
      ozon_product_id: 9_876_543_211,
      offer_id: @second_sku.sku_code,
      name: "第二个 Ozon 绑定商品",
      raw_json: { "sku" => "OZON-SKU-#{@second_sku_code}" },
      synced_at: Time.zone.parse("2026-06-01 09:00:00")
    )
    Ec::SkuProduct.create!(
      sku_code: @second_sku.sku_code,
      store: @sales_store,
      product_id: "9876543211",
      offer_id: @second_sku.sku_code,
      platform_sku_id: "OZON-SKU-#{@second_sku_code}",
      product_name: "第二个 Ozon 绑定商品"
    )

  end

  teardown do
    Ec::SkuInventoryLevel.where(sku_code: @sku.sku_code).delete_all if defined?(Ec::SkuInventoryLevel)
    Ec::OrderItem.joins(:order).where(ec_orders: { store_id: [@sales_store&.id, @wb_sales_store&.id] }).delete_all
    Ec::OrderFulfillment.joins(:order).where(ec_orders: { store_id: [@sales_store&.id, @wb_sales_store&.id] }).delete_all
    Ec::Order.where(store_id: [@sales_store&.id, @wb_sales_store&.id]).delete_all
    Ec::SkuProduct.where(store_id: [@sales_store&.id, @wb_sales_store&.id]).delete_all if defined?(Ec::SkuProduct)
    RawOzon::Product.where(account_id: @sales_ozon_account&.id).delete_all
    RawOzon::Return.where(account_id: @sales_ozon_account&.id).delete_all
    RawOzon::SupplyOrder.where(account_id: @sales_ozon_account&.id).delete_all
    RawWb::GoodsReturn.where(account_id: @wb_sales_store&.wb_raw_account_id).delete_all
    @sales_ozon_account&.destroy
    @sales_store&.destroy
    @wb_sales_store&.destroy
    @sales_wb_account&.destroy
    Ec::SkuPlatformCost.where(sku_code: @sku.sku_code).delete_all
    Ec::SkuPredictedCost.where(sku_code: @sku.sku_code).delete_all if defined?(Ec::SkuPredictedCost)
    Ec::SkuCost.where(sku_code: @sku.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: [@sku.sku_code, @second_sku.sku_code]).delete_all if defined?(Ec::SkuBatch)
    Ec::InventorySnapshot.where(sku_code: @sku.sku_code).delete_all
    Ec::InventoryTotal.where(sku_code: @sku.sku_code).delete_all
    Ec::InventorySnapshot.where(sku_code: @second_sku.sku_code).delete_all
    Ec::InventoryTotal.where(sku_code: @second_sku.sku_code).delete_all
    @second_sku&.destroy
    @sku&.destroy
    UserRole.joins(:user).where("users.email LIKE ?", "reports-#{@sku_code.downcase}%").delete_all
    User.where("email LIKE ?", "reports-#{@sku_code.downcase}%").delete_all
  end

  test "inventory report renders inventory overview totals" do
    wb_fbw_fulfillment = @wb_sales_order.fulfillments.create!(
      platform: "wb",
      store: @wb_sales_store,
      external_fulfillment_id: "WB-SALE-F-#{@sku_code}",
      fulfillment_key: "wb:#{@wb_sales_store.id}:WB-SALE-F-#{@sku_code}",
      fulfillment_type: "fbw",
      status: "delivered"
    )
    @wb_sales_order.items.update_all(fulfillment_id: wb_fbw_fulfillment.id)
    wb_fbs_order = Ec::Order.create!(
      platform: "wb",
      store: @wb_sales_store,
      external_order_id: "WB-FBS-SALE-#{@sku_code}",
      external_order_number: "WB-FBS-SALE-#{@sku_code}",
      order_key: "wb:#{@wb_sales_store.id}:WB-FBS-SALE-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-09 09:00:00"),
      synced_at: Time.zone.parse("2026-06-09 09:10:00")
    )
    wb_fbs_fulfillment = wb_fbs_order.fulfillments.create!(
      platform: "wb",
      store: @wb_sales_store,
      external_fulfillment_id: "WB-FBS-SALE-F-#{@sku_code}",
      fulfillment_key: "wb:#{@wb_sales_store.id}:WB-FBS-SALE-F-#{@sku_code}",
      fulfillment_type: "fbs",
      status: "delivered"
    )
    wb_fbs_order.items.create!(
      fulfillment: wb_fbs_fulfillment,
      platform: "wb",
      store: @wb_sales_store,
      external_item_id: "WB-FBS-SALE-I-#{@sku_code}",
      platform_sku_id: "123456",
      offer_id: "WB-OFFER-#{@sku_code}",
      product_name_source: "销量统计 WB FBS 测试商品",
      quantity: 5,
      unit_price: 50,
      payout: 200,
      commission_amount: 20,
      discount_amount: 8,
      currency_code: "BYN"
    )
    ozon_cancelled_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "CANCEL-OZON-#{@sku_code}",
      external_order_number: "CANCEL-OZON-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:CANCEL-OZON-#{@sku_code}",
      order_status: "cancelled",
      ordered_at: Time.zone.parse("2026-06-09 10:00:00"),
      synced_at: Time.zone.parse("2026-06-09 10:10:00")
    )
    ozon_cancelled_order.items.create!(
      platform: "ozon",
      store: @sales_store,
      external_item_id: "CANCEL-OZON-I-#{@sku_code}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@sku_code}",
      product_name_source: "取消 Ozon 测试商品",
      quantity: 11,
      unit_price: 100,
      payout: 0,
      commission_amount: 0,
      discount_amount: 0,
      currency_code: "BYN"
    )
    wb_cancelled_order = Ec::Order.create!(
      platform: "wb",
      store: @wb_sales_store,
      external_order_id: "CANCEL-WB-#{@sku_code}",
      external_order_number: "CANCEL-WB-#{@sku_code}",
      order_key: "wb:#{@wb_sales_store.id}:CANCEL-WB-#{@sku_code}",
      order_status: "cancelled",
      ordered_at: Time.zone.parse("2026-06-09 11:00:00"),
      synced_at: Time.zone.parse("2026-06-09 11:10:00")
    )
    wb_cancelled_order.items.create!(
      fulfillment: wb_cancelled_order.fulfillments.create!(
        platform: "wb",
        store: @wb_sales_store,
        external_fulfillment_id: "CANCEL-WB-F-#{@sku_code}",
        fulfillment_key: "wb:#{@wb_sales_store.id}:CANCEL-WB-F-#{@sku_code}",
        fulfillment_type: "fbs",
        status: "cancelled"
      ),
      platform: "wb",
      store: @wb_sales_store,
      external_item_id: "CANCEL-WB-I-#{@sku_code}",
      platform_sku_id: "123456",
      offer_id: "WB-OFFER-#{@sku_code}",
      product_name_source: "取消 WB 测试商品",
      quantity: 13,
      unit_price: 50,
      payout: 0,
      commission_amount: 0,
      discount_amount: 0,
      currency_code: "BYN"
    )
    RawOzon::Return.create!(
      account: @sales_ozon_account,
      return_id: 30_000_000 + @sku_code.hash.abs % 1_000_000,
      return_schema: "FBO",
      return_type: "Return",
      posting_number: "INV-OZON-RETURN-#{@sku_code}",
      ozon_sku: 3_902_460_130,
      offer_id: "OFFER-#{@sku_code}",
      product_name: "Ozon 绑定商品",
      quantity: 2,
      raw_json: {},
      synced_at: Time.zone.parse("2026-06-22 09:00:00")
    )
    RawOzon::Return.create!(
      account: @sales_ozon_account,
      return_id: 31_000_000 + @sku_code.hash.abs % 1_000_000,
      return_schema: "FBO",
      return_type: "Return",
      posting_number: "CANCEL-OZON-#{@sku_code}",
      ozon_sku: 3_902_460_130,
      offer_id: "OFFER-#{@sku_code}",
      product_name: "Ozon 取消订单退货商品",
      quantity: 7,
      raw_json: {},
      synced_at: Time.zone.parse("2026-06-22 09:05:00")
    )
    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "LIST-#{@sku_code}",
      status: "received",
      purchased_quantity: 30,
      received_quantity: 24,
      purchase_unit_price_cny: 1
    )
    RawOzon::SupplyOrder.create!(
      account: @sales_ozon_account,
      supply_order_id: "INV-SUPPLY-#{@sku_code}",
      status: "COMPLETED",
      items: { "3902460130" => 6 },
      raw_json: {},
      synced_at: Time.zone.parse("2026-06-22 08:00:00")
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      account_id: @sales_ozon_account.id,
      store_name: @sales_store.store_name,
      store: @sales_store,
      fulfillment_type: "fbo",
      quantity: 8,
      is_latest: true,
      synced_at: User.profile_time_zone(@current_user.time_zone).local(2026, 6, 22, 10, 0),
      metadata: {}
    )

    get "/reports/inventory", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "库存报表"
    assert_select "th", "采购"
    assert_select "th", "WB_FBW"
    assert_select "th", "Ozon_FBO"
    assert_select "th", "白俄可用"
    assert_select "tbody tr", count: 2
    assert_select "td", @sku_code
    assert_select "a[href=?]", "/reports/skus/#{@sku_code}?tab=inventory", @sku_code
    assert_match(/#{Regexp.escape(@sku_code)}.*?<td class="numeric">5<\/td>.*?<td class="numeric">3<\/td>.*?<td class="numeric">0<\/td>.*?<td class="numeric">8<\/td>.*?<td class="numeric">2<\/td>.*?<td class="numeric">2<\/td>.*?<td class="numeric">8<\/td>/m, response.body)
    assert_select "td", "24"
    assert_match(/#{Regexp.escape(@sku_code)}.*?<td class="numeric">16<\/td>.*?<td class="numeric">8<\/td>.*?<td class="numeric">8<\/td>/m, response.body)
  end

  test "inventory report wb fulfillment sales ignore sku code without sku product binding" do
    fulfillment = @wb_sales_order.fulfillments.create!(
      platform: "wb",
      store: @wb_sales_store,
      external_fulfillment_id: "WB-UNBOUND-F-#{@sku_code}",
      fulfillment_key: "wb:#{@wb_sales_store.id}:WB-UNBOUND-F-#{@sku_code}",
      fulfillment_type: "fbs",
      status: "delivered"
    )
    unbound_order = Ec::Order.create!(
      platform: "wb",
      store: @wb_sales_store,
      external_order_id: "WB-UNBOUND-SALE-#{@sku_code}",
      external_order_number: "WB-UNBOUND-SALE-#{@sku_code}",
      order_key: "wb:#{@wb_sales_store.id}:WB-UNBOUND-SALE-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-09 09:00:00"),
      synced_at: Time.zone.parse("2026-06-09 09:10:00")
    )
    unbound_order.items.create!(
      fulfillment: fulfillment,
      platform: "wb",
      store: @wb_sales_store,
      external_item_id: "WB-UNBOUND-SALE-I-#{@sku_code}",
      platform_sku_id: "WB-UNBOUND-#{@sku_code}",
      offer_id: "WB-OFFER-#{@sku_code}",
      sku_code: @sku.sku_code,
      product_name_source: "未绑定 WB 履约商品",
      quantity: 9,
      unit_price: 50,
      payout: 450,
      commission_amount: 45,
      discount_amount: 0,
      currency_code: "BYN"
    )

    get "/reports/inventory", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_match(/#{Regexp.escape(@sku_code)}.*?<td class="numeric">0<\/td>.*?<td class="numeric">3<\/td>/m, response.body)
    assert_select "td", { text: "9", count: 0 }
  ensure
    unbound_order&.items&.delete_all
    unbound_order&.destroy
    fulfillment&.destroy
  end

  test "inventory report filters by sku query" do
    get "/reports/inventory", params: { sku: @sku_code.downcase }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='sku'][value=?]", @sku_code.downcase
    assert_select "td", @sku_code
    assert_select "td", { text: @second_sku_code, count: 0 }
    assert_select "tbody tr", count: 1
  end

  test "inventory report renders cache updated time and refresh button" do
    @current_user.update!(time_zone: "Europe/Moscow")
    sign_in @current_user
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      account_id: @sales_ozon_account.id,
      store_name: @sales_store.store_name,
      store: @sales_store,
      fulfillment_type: "fbo",
      quantity: 4,
      is_latest: true,
      synced_at: Time.utc(2026, 5, 30, 10, 0, 0),
      metadata: {}
    )

    get "/reports/inventory", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "th", "缓存更新时间"
    assert_select "form[action=?][method=?]", "/reports/inventory/#{@sku_code}/refresh_cache", "post"
    assert_match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}/, response.body)
  end

  test "inventory report caches each sku row until refresh" do
    cache_store = ActiveSupport::Cache::MemoryStore.new
    original_cache_store = Rails.cache

    Rails.cache = cache_store

    begin
      get "/reports/inventory", headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "td", { text: "24", count: 0 }

      Ec::SkuBatch.create!(
        sku_code: @sku.sku_code,
        batch_code: "CACHE-#{@sku_code}",
        status: "received",
        purchased_quantity: 30,
        received_quantity: 24,
        purchase_unit_price_cny: 1
      )

      sign_in @current_user
      get "/reports/inventory", headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "td", { text: "24", count: 0 }

      sign_in @current_user
      post "/reports/inventory/#{@sku_code}/refresh_cache", params: { sku: @sku_code.downcase }, headers: { "Accept" => "text/html" }

      assert_redirected_to "/reports/inventory?sku=#{@sku_code.downcase}"

      sign_in @current_user
      get "/reports/inventory", params: { sku: @sku_code.downcase }, headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select "td", "24"
    ensure
      Rails.cache = original_cache_store
    end
  end

  test "skus report renders sku master data" do
    get "/reports/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU 主数据"
    assert_select "a[href=?]", "/reports/skus/#{@sku_code}", @sku_code
    assert_select "td", @sku_code
    assert_select "td", "测试商品"
    assert_select "td", "Тестовый товар"
    assert_select ".status-pill", "上架"
  end

  test "sku detail renders basic configuration by default" do
    assignment = Ec::SkuStoreAssignment.create!(
      sku_code: @sku.sku_code,
      store_key: "ozon1_nevastal",
      platform: "ozon",
      external_id: "EXT-#{@sku_code}",
      listed_at: Date.new(2026, 6, 1),
      owner_name: "运营 #{@sku_code}",
      is_active: true
    )

    get "/reports/skus/#{@sku.sku_code}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @sku.sku_code
    assert_select ".sku-detail-tabs a[aria-current='page']", "基础配置"
    assert_select "dt", "中文名"
    assert_select "dd", "测试商品"
    assert_select "dt", "俄文名"
    assert_select "dd", "Тестовый товар"
    assert_select "td", assignment.store_display_name
    assert_select "td", "EXT-#{@sku_code}"
    assert_select "td", "2026-06-01"
  ensure
    assignment&.destroy
  end

  test "sku detail renders platform product bindings through shared table" do
    get "/reports/skus/#{@sku.sku_code}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h2", "平台商品绑定"
    assert_select "th", "商品属性"
    assert_select "th", "店铺链接"
    assert_select "td", "销量统计 Ozon 店 #{@sku_code}"
    assert_select "td", "Ozon 绑定商品"
    binding = Ec::SkuProduct.find_by!(sku_code: @sku.sku_code, store: @sales_store)
    assert_select "a[href=?]", "/erp/platform_products/ozon/#{@sales_store.id}/#{binding.product_id}", "查看属性"
    assert_select "a[href=?][target=?]", "https://seller.ozon.ru/app/products/#{binding.platform_sku_id}/edit/general-info", "_blank"
    assert_select "a[href=?]", "/erp/skus/#{@sku.id}/products"
  end

  test "sku detail localizes basic tab in english" do
    assignment = Ec::SkuStoreAssignment.create!(
      sku_code: @sku.sku_code,
      store_key: "ozon1_nevastal",
      platform: "ozon",
      external_id: "EXT-#{@sku_code}",
      listed_at: Date.new(2026, 6, 1),
      owner_name: "运营 #{@sku_code}",
      is_active: true
    )

    get "/reports/skus/#{@sku.sku_code}", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".resource-eyebrow", "SKU Details"
    assert_select "a.button", "Back to list"
    assert_select "a.button", "Edit profile"
    assert_select ".status-pill", "Active"
    assert_select ".summary-label", "Last 30 days net sales"
    assert_select ".sku-detail-tabs a[aria-current='page']", "Basic"
    assert_select "h2", "Basic information"
    assert_select "dt", "Chinese name"
    assert_select "dt", "Status"
    assert_select "dd", "Active"
    assert_select "h2", "Product attributes"
    assert_select "dt", "Owner"
    assert_select "h2", "Store listing configuration"
    assert_select "th", "External ID"
    assert_select "td", "Enabled"
  ensure
    assignment&.destroy
  end

  test "sku detail renders cost tab" do
    Ec::SkuPredictedCost.create!(
      sku_code: @sku.sku_code,
      cost_money: 15.75,
      cost_currency: "USD",
      effective_from: Date.new(2026, 6, 1),
      effective_to: Date.new(2026, 6, 30),
      note: "首批测算"
    )

    get "/reports/skus/#{@sku.sku_code}", params: { tab: "costs" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".sku-detail-tabs a[aria-current='page']", "成本情况"
    assert_select "h2", "预测成本配置"
    assert_select "turbo-frame#erp_modal"
    assert_select "a[href=?][data-turbo-frame=?]", "/reports/skus/#{@sku.sku_code}/predicted_costs/new", "erp_modal", "新增预测成本"
    assert_select "form[action=?]", "/reports/skus/#{@sku.sku_code}/predicted_costs", count: 0
    assert_select "td", "15.75"
    assert_select "td", "USD"
    assert_select "td", "2026-06-01"
    assert_select "td", "2026-06-30"
    assert_select "td", "首批测算"
    assert_select "h2", "SKU 基础成本"
    assert_select "h2", "WB 成本"
    assert_select "h2", "Ozon 成本"
    assert_select "td", "fbo"
    assert_select "td", "fbs"
    assert_select "td", "1000.00"
    assert_select "td", "1200.00"
  end

  test "sku detail localizes costs stores and trend tabs in english" do
    Ec::SkuPredictedCost.create!(
      sku_code: @sku.sku_code,
      cost_money: 15.75,
      cost_currency: "USD",
      effective_from: Date.new(2026, 6, 1),
      note: "首批测算"
    )

    get "/reports/skus/#{@sku.sku_code}", params: { locale: "en", tab: "costs" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".sku-detail-tabs a[aria-current='page']", "Costs"
    assert_select "h2", "Predicted cost configuration"
    assert_select "a[href=?][data-turbo-frame=?]", "/reports/skus/#{@sku.sku_code}/predicted_costs/new?locale=en", "erp_modal", "Add predicted cost"
    assert_select "th", "Predicted cost"
    assert_select "h2", "SKU base cost"

    sign_in @current_user
    get "/reports/skus/#{@sku.sku_code}", params: {
      locale: "en",
      tab: "stores",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".sku-detail-tabs a[aria-current='page']", "Store sales"
    assert_select "label", "Start date"
    assert_select "option", "All platforms"
    assert_select "button", "Search"
    assert_select ".summary-label", "Units sold"
    assert_select "h2", "Store sales"
    assert_select "th", "Last ordered at"

    sign_in @current_user
    get "/reports/skus/#{@sku.sku_code}", params: {
      locale: "en",
      tab: "trend",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".sku-detail-tabs a[aria-current='page']", "Sales trend"
    assert_select "label", "Period"
    assert_select "option", "Day"
    assert_select "option", "Summary"
    assert_select "h2", "Net sales / Revenue trend"
    assert_select "h2", "Trend details"
    assert_select "script#sku-detail-sales-chart-data[type=?]", "application/json", /Net sales/
    assert_select "script#sku-detail-sales-chart-data[type=?]", "application/json", /Revenue/
  end

  test "new sku predicted cost renders modal form" do
    get "/reports/skus/#{@sku.sku_code}/predicted_costs/new", headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal[role='dialog']"
    assert_select "h2", "新增预测成本"
    assert_select "form[action=?][method=?][data-turbo-frame=?]", "/reports/skus/#{@sku.sku_code}/predicted_costs", "post", "_top"
    assert_select "input[name='ec_sku_predicted_cost[cost_money]']"
    assert_select "select[name='ec_sku_predicted_cost[cost_currency]'] option[selected]", "CNY"
    assert_select "input[name='ec_sku_predicted_cost[effective_from]']"
  end

  test "new sku predicted cost localizes modal form in english" do
    get "/reports/skus/#{@sku.sku_code}/predicted_costs/new", params: { locale: "en" }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "h2", "Add predicted cost"
    assert_select "button[aria-label=?]", "Close"
    assert_select "label", "Predicted cost"
    assert_select "label", "Currency"
    assert_select "label", "Start date"
    assert_select "input[type='submit'][value=?]", "Save"
    assert_select "button", "Cancel"
  end

  test "creates sku predicted cost with default currency from cost tab" do
    assert_difference -> { Ec::SkuPredictedCost.where(sku_code: @sku.sku_code).count }, 1 do
      post "/reports/skus/#{@sku.sku_code}/predicted_costs", params: {
        ec_sku_predicted_cost: {
          cost_money: "18.50",
          effective_from: "2026-07-01",
          effective_to: "2026-07-31",
          note: "旺季预测"
        }
      }, headers: { "Accept" => "text/html" }
    end

    created = Ec::SkuPredictedCost.where(sku_code: @sku.sku_code).order(:created_at).last
    assert_equal 18.50.to_d, created.cost_money
    assert_equal "CNY", created.cost_currency
    assert_equal Date.new(2026, 7, 1), created.effective_from
    assert_equal Date.new(2026, 7, 31), created.effective_to
    assert_equal "旺季预测", created.note
    assert_redirected_to "/reports/skus/#{@sku.sku_code}?tab=costs"
  end

  test "sku detail renders store sales tab without other sku data" do
    extra_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "EXTRA-SALE-#{@sku_code}",
      external_order_number: "EXTRA-SALE-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:EXTRA-SALE-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-08 09:00:00"),
      synced_at: Time.zone.parse("2026-06-08 09:10:00")
    )
    extra_order.items.create!(
      platform: "ozon",
      store: @sales_store,
      external_item_id: "EXTRA-SALE-I-#{@sku_code}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@sku_code}",
      sku_code: @sku.sku_code,
      product_name_source: "销量统计测试商品",
      quantity: 5,
      unit_price: 100,
      payout: 400,
      commission_amount: 50,
      discount_amount: 25,
      currency_code: "BYN"
    )

    get "/reports/skus/#{@sku.sku_code}", params: {
      tab: "stores",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".sku-detail-tabs a[aria-current='page']", "各店铺销量情况"
    assert_select "td", { text: "销量统计 Ozon 店 #{@sku_code}", count: 1 }
    assert_select "td", "销量统计 WB 店 #{@sku_code}"
    assert_select "td", "Ozon"
    assert_select "td", "WB"
    assert_select "td", "6"
    assert_select "td", "3"
    assert_select "td", { text: @second_sku.sku_code, count: 0 }
    assert_select "td", { text: "第二个销量统计测试商品", count: 0 }
  ensure
    extra_order&.items&.delete_all
    extra_order&.destroy
  end

  test "sku detail renders inventory overview tab" do
    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "INV-#{@sku_code}",
      status: "received",
      purchased_quantity: 12,
      received_quantity: 10,
      purchase_unit_price_cny: 1
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      account_id: @sales_ozon_account.id,
      store_name: @sales_store.store_name,
      fulfillment_type: "fbo",
      quantity: 4,
      is_latest: true,
      synced_at: User.profile_time_zone(@current_user.time_zone).local(2026, 6, 22, 10, 0),
      metadata: {}
    )

    get "/reports/skus/#{@sku.sku_code}", params: { tab: "inventory" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".sku-detail-tabs a[aria-current='page']", "库存概况"
    assert_select ".summary-label", "入库数量"
    assert_select ".summary-value", "10"
    assert_select "h2", "库存校对汇总"
    assert_select "td", "销量统计 Ozon 店 #{@sku_code}"
    assert_select "td", "4"
    assert_select "h2", "最新平台在库"
    assert_select "td", "FBO"
    assert_select "td", "2026-06-22 10:00"
  ensure
    Ec::SkuBatch.where(batch_code: "INV-#{@sku_code}").delete_all
  end

  test "sku detail inventory overview counts order items linked by sku product ids" do
    other_sku = Ec::Sku.create!(
      sku_code: "OTHER-INV-#{@sku_code}",
      product_name: "库存概况其他商品"
    )
    other_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "OTHER-INV-SALE-#{@sku_code}",
      external_order_number: "OTHER-INV-SALE-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:OTHER-INV-SALE-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-04 10:00:00"),
      synced_at: Time.zone.parse("2026-06-04 10:10:00")
    )
    other_order.items.create!(
      platform: "ozon",
      store: @sales_store,
      external_item_id: "OTHER-INV-SALE-I-#{@sku_code}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@sku_code}",
      sku_code: other_sku.sku_code,
      product_name_source: "库存概况其他商品",
      quantity: 9,
      unit_price: 100,
      payout: 900,
      commission_amount: 90,
      discount_amount: 0,
      currency_code: "BYN"
    )

    get "/reports/skus/#{@sku.sku_code}", params: { tab: "inventory" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_match(/销量统计 Ozon 店 #{@sku_code}.*?<td>11<\/td>/m, response.body)
  ensure
    other_order&.items&.delete_all
    other_order&.destroy
    Ec::Sku.with_deleted.where(sku_code: other_sku&.sku_code).delete_all
  end

  test "sku detail inventory overview ignores sku code without sku product id binding" do
    unbound_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "UNBOUND-INV-SALE-#{@sku_code}",
      external_order_number: "UNBOUND-INV-SALE-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:UNBOUND-INV-SALE-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-04 10:00:00"),
      synced_at: Time.zone.parse("2026-06-04 10:10:00")
    )
    unbound_order.items.create!(
      platform: "ozon",
      store: @sales_store,
      external_item_id: "UNBOUND-INV-SALE-I-#{@sku_code}",
      platform_sku_id: "UNBOUND-INV-#{@sku_code}",
      offer_id: "UNBOUND-INV-OFFER-#{@sku_code}",
      sku_code: @sku.sku_code,
      product_name_source: "库存概况未绑定商品",
      quantity: 9,
      unit_price: 100,
      payout: 900,
      commission_amount: 90,
      discount_amount: 0,
      currency_code: "BYN"
    )

    get "/reports/skus/#{@sku.sku_code}", params: { tab: "inventory" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_match(/销量统计 Ozon 店 #{@sku_code}.*?<td>2<\/td>/m, response.body)
    assert_select "td", { text: "9", count: 0 }
  ensure
    unbound_order&.items&.delete_all
    unbound_order&.destroy
  end

  test "sku detail inventory overview reads platform returns from raw return tables" do
    RawOzon::Return.create!(
      account: @sales_ozon_account,
      return_id: 10_000_000 + @sku_code.hash.abs % 1_000_000,
      return_schema: "FBO",
      return_type: "Return",
      posting_number: "OZON-RETURN-#{@sku_code}",
      ozon_sku: 3_902_460_130,
      offer_id: "OFFER-#{@sku_code}",
      product_name: "Ozon 绑定商品",
      quantity: 2,
      raw_json: {},
      synced_at: Time.zone.parse("2026-06-22 09:00:00")
    )
    RawWb::GoodsReturn.create!(
      account_id: @wb_sales_store.wb_raw_account_id,
      shk_id: 20_000_000 + @sku_code.hash.abs % 1_000_000,
      nm_id: 123_456,
      barcode: "WB-RETURN-#{@sku_code}",
      status: "ready_to_return",
      synced_at: Time.zone.parse("2026-06-22 09:00:00")
    )

    get "/reports/skus/#{@sku.sku_code}", params: { tab: "inventory" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", "销量统计 Ozon 店 #{@sku_code}"
    assert_select "td", "销量统计 WB 店 #{@sku_code}"
    assert_select ".summary-value", "3"
    assert_match(/销量统计 Ozon 店 #{@sku_code}.*?<td>2<\/td>/m, response.body)
    assert_match(/销量统计 WB 店 #{@sku_code}.*?<td>1<\/td>/m, response.body)
  end

  test "sku detail store sales ignores unbound order item sku code" do
    unbound_product_id = "9876543221"
    RawOzon::Product.create!(
      account: @sales_ozon_account,
      ozon_product_id: unbound_product_id,
      offer_id: "UNBOUND-OFFER-#{@sku_code}",
      name: "Ozon 未绑定商品",
      raw_json: { "sku" => "3902460131" },
      synced_at: Time.zone.parse("2026-06-01 09:00:00")
    )
    unbound_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "UNBOUND-SALE-#{@sku_code}",
      external_order_number: "UNBOUND-SALE-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:UNBOUND-SALE-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-04 10:00:00"),
      synced_at: Time.zone.parse("2026-06-04 10:10:00")
    )
    unbound_order.items.create!(
      platform: "ozon",
      store: @sales_store,
      external_item_id: "UNBOUND-SALE-I-#{@sku_code}",
      platform_sku_id: "3902460131",
      offer_id: "UNBOUND-OFFER-#{@sku_code}",
      sku_code: @sku.sku_code,
      product_name_source: "未绑定商品",
      quantity: 9,
      unit_price: 100,
      payout: 900,
      commission_amount: 90,
      discount_amount: 0,
      currency_code: "BYN"
    )

    get "/reports/skus/#{@sku.sku_code}", params: {
      tab: "stores",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", { text: "2026-06-04", count: 0 }
    assert_select "td", { text: "9", count: 0 }
    assert_select "td", { text: "900.00", count: 0 }
  ensure
    unbound_order&.items&.delete_all
    unbound_order&.destroy
    RawOzon::Product.where(account_id: @sales_ozon_account&.id, ozon_product_id: unbound_product_id).delete_all
  end

  test "sku detail renders sales trend tab" do
    get "/reports/skus/#{@sku.sku_code}", params: {
      tab: "trend",
      period: "week",
      grain: "platform",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".sku-detail-tabs a[aria-current='page']", "销量历史趋势"
    assert_select "script[src*=?]", "echarts"
    assert_select "#sku-detail-sales-chart[data-chart='sku-detail-sales']"
    assert_select "script#sku-detail-sales-chart-data[type=?]", "application/json", /净销量/
    assert_select "script#sku-detail-sales-chart-data[type=?]", "application/json", /销售额/
    assert_select "td", @sku.sku_code
    assert_select "td", "2026-06-01"
    assert_select "td", "2026-06-08"
    assert_select "td", { text: @second_sku.sku_code, count: 0 }
  end

  test "sku detail returns not found for missing sku" do
    get "/reports/skus/MISSING-#{@sku_code}", headers: { "Accept" => "text/html" }

    assert_response :not_found
  end

  test "costs report renders sku wb and ozon costs" do
    get "/reports/costs", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "成本报表"
    assert_select "h2", "SKU 成本"
    assert_select "h2", "WB 成本"
    assert_select "h2", "Ozon 成本"
    assert_select "td", @sku_code
    assert_select "td", "fbo"
    assert_select "td", "fbs"
    assert_select "td", "100.00"
    assert_select "td", "120.00"
  end

  test "sku sales report renders chart and grouped sales metrics" do
    get "/reports/sku_sales", params: {
      sku_codes: [@sku.sku_code],
      grain: "store",
      period: "day",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU 销量统计"
    assert_select "form[action=?][method=?]", "/reports/sku_sales", "get"
    assert_select "select[name=?]", "period"
    assert_select "select[name=?]", "grain"
    assert_select "select[name=?][multiple]", "sku_codes[]"
    assert_select "script[src*=?]", "echarts"
    assert_select "#sku-sales-chart[data-chart='sku-sales']"
    assert_select "script#sku-sales-chart-data[type=?]", "application/json", /销量统计 Ozon 店 #{@sku_code}/
    assert_select "script#sku-sales-chart-data[type=?]", "application/json", /销量统计 WB 店 #{@sku_code}/
    assert_select "script#sku-sales-chart-data[type=?]", "application/json", /净销量/
    assert_select "script#sku-sales-chart-data[type=?]", "application/json", /销售额/
    assert_select "td", @sku.sku_code
    assert_select "td", "Ozon"
    assert_select "td", "销量统计 Ozon 店 #{@sku_code}"
    assert_select "td", "2026-06-01"
    assert_select "td", "2"
    assert_select "td", "1"
    assert_select "td", "1"
    assert_select "td", "2"
    assert_select "td", "300.00"
    assert_select "td", "240.00"
    assert_select "td", "30.00"
    assert_select "td", "15.00"
    assert_select "td", "fbo / fbs"
    assert_select "td", "WB"
    assert_select "td", "2026-06-08"
    assert_select "td", "3"
    assert_select "td", { text: @second_sku.sku_code, count: 0 }
  end

  test "sku sales report filters date range in current user time zone" do
    boundary_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "REPORT-TZ-#{@sku_code}",
      external_order_number: "REPORT-TZ-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:REPORT-TZ-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.utc(2026, 6, 1, 16, 30, 0),
      synced_at: Time.utc(2026, 6, 1, 16, 35, 0)
    )
    boundary_order.items.create!(
      platform: "ozon",
      store: @sales_store,
      external_item_id: "REPORT-TZ-I-#{@sku_code}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@sku_code}",
      product_name_source: "用户时区边界商品",
      quantity: 7,
      unit_price: 100,
      payout: 700,
      commission_amount: 70,
      discount_amount: 0,
      currency_code: "BYN"
    )

    get "/reports/sku_sales", params: {
      sku_codes: [@sku.sku_code],
      grain: "store",
      period: "day",
      from_date: "2026-06-02",
      to_date: "2026-06-02"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", "2026-06-02"
    assert_select "td", "7"

    @current_user.update!(time_zone: "UTC")
    sign_in @current_user

    get "/reports/sku_sales", params: {
      sku_codes: [@sku.sku_code],
      grain: "store",
      period: "day",
      from_date: "2026-06-02",
      to_date: "2026-06-02"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", { text: "2026-06-02", count: 0 }
    assert_select "td", { text: "7", count: 0 }
  ensure
    boundary_order&.items&.delete_all
    boundary_order&.destroy
  end

  test "sku sales report groups periods in current user time zone" do
    boundary_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "REPORT-GROUP-TZ-#{@sku_code}",
      external_order_number: "REPORT-GROUP-TZ-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:REPORT-GROUP-TZ-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.utc(2026, 6, 1, 16, 30, 0),
      synced_at: Time.utc(2026, 6, 1, 16, 35, 0)
    )
    boundary_order.items.create!(
      platform: "ozon",
      store: @sales_store,
      external_item_id: "REPORT-GROUP-TZ-I-#{@sku_code}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@sku_code}",
      product_name_source: "用户时区分组商品",
      quantity: 7,
      unit_price: 100,
      payout: 700,
      commission_amount: 70,
      discount_amount: 0,
      currency_code: "BYN"
    )

    get "/reports/sku_sales", params: {
      sku_codes: [@sku.sku_code],
      grain: "store",
      period: "day",
      from_date: "2026-06-01",
      to_date: "2026-06-02"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_match(/2026-06-02.*?<td>7<\/td>/m, response.body)
  ensure
    boundary_order&.items&.delete_all
    boundary_order&.destroy
  end

  test "sku sales report localizes visible chrome in english" do
    get "/reports/sku_sales", params: {
      locale: "en",
      sku_codes: [@sku.sku_code],
      grain: "store",
      period: "day",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU Sales"
    assert_select "label", "Analysis grain"
    assert_select "option", "Store"
    assert_select "label", "Platform"
    assert_select "option", "All platforms"
    assert_select "label", "Period"
    assert_select "option", "Day"
    assert_select "label", "Start date"
    assert_select "button", "Search"
    assert_select ".summary-label", "Units sold"
    assert_select ".summary-label", "Returned units"
    assert_select ".summary-label", "Net sales"
    assert_select ".summary-label", "Revenue"
    assert_select "h2", "Net sales / Revenue trend"
    assert_select "h2", "Details"
    assert_select "th", "Period"
    assert_select "th", "Product name"
    assert_select "th", "Average price"
    assert_select "th", "Fulfillment mode"
    assert_select "script#sku-sales-chart-data[type=?]", "application/json", /Net sales/
    assert_select "script#sku-sales-chart-data[type=?]", "application/json", /Revenue/
  end

  test "sku sales report uses product bindings instead of order item sku code" do
    unbound_product_id = "9876543222"
    RawOzon::Product.create!(
      account: @sales_ozon_account,
      ozon_product_id: unbound_product_id,
      offer_id: "UNBOUND-SALES-OFFER-#{@sku_code}",
      name: "Ozon 未绑定销量商品",
      raw_json: { "sku" => "3902460131" },
      synced_at: Time.zone.parse("2026-06-01 09:00:00")
    )
    unbound_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "UNBOUND-SALES-#{@sku_code}",
      external_order_number: "UNBOUND-SALES-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:UNBOUND-SALES-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-04 10:00:00"),
      synced_at: Time.zone.parse("2026-06-04 10:10:00")
    )
    unbound_order.items.create!(
      platform: "ozon",
      store: @sales_store,
      external_item_id: "UNBOUND-SALES-I-#{@sku_code}",
      platform_sku_id: "3902460131",
      offer_id: "UNBOUND-SALES-OFFER-#{@sku_code}",
      sku_code: @sku.sku_code,
      product_name_source: "未绑定销量商品",
      quantity: 9,
      unit_price: 100,
      payout: 900,
      commission_amount: 90,
      discount_amount: 0,
      currency_code: "BYN"
    )

    get "/reports/sku_sales", params: {
      sku_codes: [@sku.sku_code],
      grain: "store",
      period: "day",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", { text: "2026-06-04", count: 0 }
    assert_select "td", { text: "9", count: 0 }
    assert_select "td", { text: "900.00", count: 0 }
  ensure
    unbound_order&.items&.delete_all
    unbound_order&.destroy
    RawOzon::Product.where(account_id: @sales_ozon_account&.id, ozon_product_id: unbound_product_id).delete_all
  end

  test "sku sales report aggregates by platform and sku grains" do
    get "/reports/sku_sales", params: {
      sku_codes: [@sku.sku_code, @second_sku.sku_code],
      grain: "platform",
      period: "week",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", "Ozon"
    assert_select "td", { text: "销量统计 Ozon 店 #{@sku_code}", count: 0 }
    assert_select "td", @sku.sku_code
    assert_select "td", @second_sku.sku_code
    assert_select "script#sku-sales-chart-data[type=?]", "application/json", /Ozon/

    sign_in @current_user
    get "/reports/sku_sales", params: {
      sku_codes: [@sku.sku_code, @second_sku.sku_code],
      grain: "sku",
      period: "week",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", { text: "Ozon", count: 0 }
    assert_select "td", { text: "WB", count: 0 }
    assert_select "td", { text: "销量统计 Ozon 店 #{@sku_code}", count: 0 }
    assert_select "td", @sku.sku_code
    assert_select "td", @second_sku.sku_code
  end

end
