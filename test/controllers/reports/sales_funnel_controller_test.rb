require "test_helper"

class Reports::SalesFunnelControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("sales-funnel-#{@token.downcase}@example.com", "manager")
    sign_in @user
    @wb_account = RawWb::SellerAccount.create!(
      name: "Funnel UI #{@token}", api_token: "wb-ui-#{@token}", is_active: true, company_type: :small
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Funnel Ozon UI #{@token}", client_id: "ozon-ui-#{@token}",
      api_key: "ozon-key-#{@token}", is_active: true, company_type: :small
    )
    @wb_store = Ec::Store.create!(
      platform: "wb", store_name: "Funnel UI #{@token}", company_type: "small",
      wb_raw_account_id: @wb_account.id, is_active: true
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon", store_name: "Funnel Ozon UI #{@token}", company_type: "small",
      ozon_raw_account_id: @ozon_account.id, is_active: true
    )
    @sku = Ec::Sku.create!(sku_code: "FUNNEL-UI-#{@token}", product_name: "系统漏斗商品")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "71001")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZON-UI-#{@token}", platform_sku_id: "81001")
  end

  teardown do
    RawWb::SalesFunnelPeriod.where(account_id: @wb_account.id).delete_all
    RawOzon::SalesFunnelPeriod.where(account_id: @ozon_account.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku.sku_code).delete_all
    Ec::Store.where(id: [@wb_store.id, @ozon_store.id]).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    @wb_account.destroy!
    @ozon_account.destroy!
    UserRole.where(user_id: @user.id).delete_all
    @user.destroy!
  end

  test "redirects to the previous complete calendar week by default" do
    get reports_sales_funnel_path, headers: { "Accept" => "text/html" }

    monday = Date.current.beginning_of_week(:monday)
    default_store_ref = SalesFunnelReports::ReportQueryRunner.store_options.first.fetch(:ref)
    assert_redirected_to reports_sales_funnel_path(
      from_date: (monday - 7.days).iso8601,
      to_date: (monday - 1.day).iso8601,
      store_ref: default_store_ref
    )
  end

  test "renders WB filters summary and platform columns" do
    RawWb::SalesFunnelPeriod.create!(
      account: @wb_account, period_start: Date.new(2026, 6, 29), period_end: Date.new(2026, 7, 5),
      nm_id: 71001, vendor_code: "UI-#{@token}", product_name: "上期平台商品名",
      open_card: 50, add_to_cart: 10, orders: 5, orders_sum: 500,
      buyouts: 4, buyouts_sum: 400, synced_at: Time.current
    )
    RawWb::SalesFunnelPeriod.create!(
      account: @wb_account, period_start: Date.new(2026, 7, 6), period_end: Date.new(2026, 7, 12),
      nm_id: 71001, vendor_code: "UI-#{@token}", product_name: "界面漏斗商品",
      open_card: 100, add_to_cart: 20, orders: 10, orders_sum: 1_000,
      buyouts: 8, buyouts_sum: 800, synced_at: Time.current
    )

    get reports_sales_funnel_path, params: {
      store_ref: "wb:#{@wb_account.id}", from_date: "2026-07-06", to_date: "2026-07-12"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "销售漏斗报表"
    assert_select "form[action=?][data-turbo-frame='sales_funnel_report_results']", reports_sales_funnel_path
    assert_select "[data-controller='time-range-selector']"
    assert_select "button[data-weekly-profit-filter-target='storeButton'][data-value=?].is-active", "wb:#{@wb_account.id}", text: "WB · Funnel UI #{@token}"
    assert_select "input[name='store_ref'][data-weekly-profit-filter-target='storeInput'][value=?]", "wb:#{@wb_account.id}"
    assert_select "turbo-frame#sales_funnel_report_results"
    assert_select ".weekly-profit-summary-card", minimum: 1
    assert_select ".weekly-profit-comparison-note", /2026-06-29 ~ 2026-07-05/
    assert_select ".weekly-profit-comparison-trend.is-positive", /100\.00% vs 上一周期/
    assert_select "th", "打开商品卡"
    assert_select "th", "成交率"
    assert_select "th", "SKU"
    assert_select ".weekly-profit-table-value", @sku.sku_code
    assert_select ".weekly-profit-table-value", "系统漏斗商品"
    assert_select ".weekly-profit-table-value", { text: "界面漏斗商品", count: 0 }
    assert_select ".weekly-profit-table-comparison.is-positive", /100\.00%/
  end

  test "returns JSON and rejects partial week boundaries" do
    get reports_sales_funnel_path(format: :json), params: {
      store_ref: "wb:#{@wb_account.id}", from_date: "2026-07-07", to_date: "2026-07-12"
    }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_equal "只能查询已完成的完整自然周", body["message"]
  end

  test "switching to an Ozon store renders Ozon-specific columns" do
    RawOzon::SalesFunnelPeriod.create!(
      account: @ozon_account, period_start: Date.new(2026, 7, 6), period_end: Date.new(2026, 7, 12),
      sku: 81001, product_name: "Ozon 界面漏斗商品", hits_view: 200, session_view: 120,
      hits_tocart: 30, ordered_units: 12, revenue: 1_200, returns_count: 2,
      cancellations: 1, synced_at: Time.current
    )

    get reports_sales_funnel_path, params: {
      store_ref: "ozon:#{@ozon_account.id}", from_date: "2026-07-06", to_date: "2026-07-12"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "button[data-weekly-profit-filter-target='storeButton'][data-value=?].is-active", "ozon:#{@ozon_account.id}", text: "Ozon · Funnel Ozon UI #{@token}"
    assert_select "input[name='store_ref'][data-weekly-profit-filter-target='storeInput'][value=?]", "ozon:#{@ozon_account.id}"
    assert_select "th", "SKU"
    assert_select "th", "访问人数"
    assert_select "th", "退货数"
    assert_select "th", { text: "成交率", count: 0 }
    assert_select ".weekly-profit-table-value", @sku.sku_code
    assert_select ".weekly-profit-table-value", "系统漏斗商品"
    assert_select ".weekly-profit-table-value", { text: "Ozon 界面漏斗商品", count: 0 }
  end
end
