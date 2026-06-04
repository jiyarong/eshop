require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @sku_code = "TST-#{SecureRandom.hex(4).upcase}"
    sign_in create_user_with_roles("reports-#{@sku_code.downcase}@example.com", "manager")
    @sku = Ec::Sku.create!(
      sku_code: @sku_code,
      product_name: "测试商品",
      product_name_ru: "Тестовый товар",
      is_active: true
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

  end

  teardown do
    Ec::SkuPlatformCost.where(sku_code: @sku.sku_code).delete_all
    Ec::SkuCost.where(sku_code: @sku.sku_code).delete_all
    Ec::InventorySnapshot.where(sku_code: @sku.sku_code).delete_all
    Ec::InventoryTotal.where(sku_code: @sku.sku_code).delete_all
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
    assert_select "td", @sku_code
    assert_select "td", "测试商品"
    assert_select "td", "Тестовый товар"
    assert_select ".status-pill", "上架"
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

end
