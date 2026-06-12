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
    @sales_store = Ec::Store.create!(
      platform: "ozon",
      store_name: "销量统计 Ozon 店 #{@sku_code}",
      company_type: "general"
    )
    @wb_sales_store = Ec::Store.create!(
      platform: "wb",
      store_name: "销量统计 WB 店 #{@sku_code}",
      company_type: "small"
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

    @inventory_total = Ec::InventoryTotal.create!(
      sku_code: @sku.sku_code,
      total_supply: 3,
      total_stock: 7,
      total_sold: 5,
      total_fbs: 1,
      total_received: 20,
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
      platform_sku_id: "OZON-SKU-#{@sku_code}",
      offer_id: @sku.sku_code,
      sku_code: @sku.sku_code,
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
      platform_sku_id: "OZON-SKU-#{@sku_code}",
      offer_id: @sku.sku_code,
      sku_code: @sku.sku_code,
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
      platform_sku_id: "WB-SKU-#{@sku_code}",
      offer_id: @sku.sku_code,
      sku_code: @sku.sku_code,
      product_name_source: "销量统计 WB 测试商品",
      quantity: 3,
      unit_price: 50,
      payout: 120,
      commission_amount: 15,
      discount_amount: 6,
      currency_code: "BYN"
    )

    @second_sku_order = Ec::Order.create!(
      platform: "ozon",
      store: @sales_store,
      external_order_id: "SECOND-SALE-#{@sku_code}",
      external_order_number: "SECOND-SALE-#{@sku_code}",
      order_key: "ozon:#{@sales_store.id}:SECOND-SALE-#{@sku_code}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-08 16:00:00"),
      synced_at: Time.zone.parse("2026-06-08 16:10:00")
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

  end

  teardown do
    Ec::OrderItem.joins(:order).where(ec_orders: { store_id: [@sales_store&.id, @wb_sales_store&.id] }).delete_all
    Ec::OrderFulfillment.joins(:order).where(ec_orders: { store_id: [@sales_store&.id, @wb_sales_store&.id] }).delete_all
    Ec::Order.where(store_id: [@sales_store&.id, @wb_sales_store&.id]).delete_all
    @sales_store&.destroy
    @wb_sales_store&.destroy
    Ec::SkuPlatformCost.where(sku_code: @sku.sku_code).delete_all
    Ec::SkuPredictedCost.where(sku_code: @sku.sku_code).delete_all if defined?(Ec::SkuPredictedCost)
    Ec::SkuCost.where(sku_code: @sku.sku_code).delete_all
    Ec::InventorySnapshot.where(sku_code: @sku.sku_code).delete_all
    Ec::InventoryTotal.where(sku_code: @sku.sku_code).delete_all
    @second_sku&.destroy
    @sku&.destroy
    UserRole.joins(:user).where("users.email LIKE ?", "reports-#{@sku_code.downcase}%").delete_all
    User.where("email LIKE ?", "reports-#{@sku_code.downcase}%").delete_all
  end

  test "inventory report renders inventory snapshot and totals" do
    get "/reports/inventory", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "库存报表"
    assert_select "td", @sku_code
    assert_select "td", "TaxiLink"
    assert_select "td", "7"
    assert_select "td", "16"
    assert_select "td", "23"
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
      platform_sku_id: "OZON-SKU-#{@sku_code}",
      offer_id: @sku.sku_code,
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
