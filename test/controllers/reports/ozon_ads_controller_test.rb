require "test_helper"
require "securerandom"

class Reports::OzonAdsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(6)
    @user = create_user_with_roles("ozon-ads-#{@token}@example.com", "manager")
    sign_in @user
    @account = RawOzon::SellerAccount.create!(client_id: "ads-page-#{@token}", api_key: @token, company_type: "small")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Ads #{@token}", company_type: "small",
      ozon_raw_account_id: @account.id, is_active: true)
    @ec_sku = Ec::Sku.create!(sku_code: "ADS-#{@token.upcase}", product_name: "Bound lamp")
    @sku_product = Ec::SkuProduct.create!(sku: @ec_sku, store: @store, platform: "ozon",
      product_id: "raw-#{@token}", platform_sku_id: "3001", product_name: "Bound lamp")
    @cpo_ec_sku = Ec::Sku.create!(sku_code: "CPO-#{@token.upcase}", product_name: "Bound towel")
    @cpo_sku_product = Ec::SkuProduct.create!(sku: @cpo_ec_sku, store: @store, platform: "ozon",
      product_id: "cpo-raw-#{@token}", platform_sku_id: "3002", product_name: "Bound towel")
    @cpc = RawOzon::AdUnit.create!(account: @account, external_id: "101", unit_type: "cpc_campaign",
      title: "CPC Test", state: "CAMPAIGN_STATE_RUNNING", billing_model: "cpc", raw_json: {}, synced_at: Time.current)
    @cpo = RawOzon::AdUnit.create!(account: @account, external_id: "201", unit_type: "cpo_selected",
      title: "CPO Test", state: "CAMPAIGN_STATE_RUNNING", billing_model: "cpo", raw_json: {}, synced_at: Time.current)
    @product = RawOzon::AdUnitProduct.create!(ad_unit: @cpc, ozon_sku_id: "3001", title: "Lamp",
      bid: 8, is_current: true, raw_json: {}, synced_at: Time.current)
    RawOzon::AdUnitProduct.create!(ad_unit: @cpo, ozon_sku_id: "3002", title: "Towel",
      bid: 10, price: 1000, is_current: true, raw_json: {}, synced_at: Time.current)
    RawOzon::AdDailyStat.create!(account: @account, ad_unit: @cpc, stat_date: Date.yesterday, cost_model: "cpc",
      impressions: 100, clicks: 10, orders_count: 2, ad_revenue: 5000, spend: 500, raw_json: {}, synced_at: Time.current)
    RawOzon::AdSkuDailyStat.create!(account: @account, ad_unit: @cpc, ozon_sku_id: "3001", stat_date: Date.yesterday,
      cost_model: "cpc", impressions: 100, clicks: 10, cart_additions: 3, orders_count: 2, ad_revenue: 5000,
      spend: 500, raw_json: {}, synced_at: Time.current)
    RawOzon::AdSkuDailyStat.create!(account: @account, ad_unit: @cpo, ozon_sku_id: "3002", stat_date: Date.yesterday,
      cost_model: "cpo", orders_count: 1, ad_revenue: 2000, spend: 200, raw_json: {}, synced_at: Time.current)
  end

  teardown do
    RawOzon::AdSkuDailyStat.where(account_id: @account.id).delete_all
    RawOzon::AdDailyStat.where(account_id: @account.id).delete_all
    RawOzon::AdUnitProduct.where(ad_unit_id: RawOzon::AdUnit.where(account_id: @account.id)).delete_all
    RawOzon::AdUnit.where(account_id: @account.id).delete_all
    Ec::SkuProduct.where(id: [@sku_product.id, @cpo_sku_product.id]).delete_all
    Ec::Sku.where(id: [@ec_sku.id, @cpo_ec_sku.id]).delete_all
    Ec::Store.where(id: @store.id).delete_all
    RawOzon::SellerAccount.where(id: @account.id).delete_all
    @user.destroy!
  end

  test "renders overview and promotion tabs from local facts" do
    get reports_ozon_ads_path, params: { store_id: @store.id, from_date: Date.yesterday, to_date: Date.yesterday }
    assert_response :success
    assert_select "h1", text: I18n.t("reports.ozon_ads.overview.title")
    assert_select "tbody tr", minimum: 1
    assert_select "[data-controller='time-range-selector']", count: 1
    assert_select ".weekly-profit-filter-tag.is-active", text: @store.store_name

    sign_in @user
    get reports_ozon_ads_cpc_path, params: { store_id: @store.id, q: "3001" }
    assert_response :success
    assert_select ".ozon-ads-filters" do
      assert_select ".weekly-profit-time-range-row", count: 1
      assert_select ".weekly-profit-date-range-field + .ozon-ads-filters__sku"
      assert_select ".ozon-ads-filters__sku ~ .ozon-ads-filters__status"
      assert_select ".ozon-ads-filters__status + .weekly-profit-filter-actions"
      assert_select "label[for='q']", text: I18n.t("reports.ozon_ads.filters.sku")
      assert_select "#ozon-ads-status-filter-trigger", text: I18n.t("shared.popover_multiselect.selected_count", count: 2)
      assert_select "input[name='statuses[]'][value='CAMPAIGN_STATE_RUNNING'][checked='checked']"
      assert_select "input[name='statuses[]'][value='CAMPAIGN_STATE_INACTIVE'][checked='checked']"
      assert_select "input[name='statuses[]'][value='CAMPAIGN_STATE_ARCHIVED'][checked='checked']", count: 0
    end
    assert_select "a[data-turbo-frame='ozon_ads_drawer']", text: "CPC Test"
    assert_select "turbo-frame#ozon_ads_drawer", count: 1

    sign_in @user
    get reports_ozon_ads_cpo_selected_path, params: { store_id: @store.id }
    assert_response :success
    assert_select "td strong", text: @cpo_ec_sku.sku_code
    assert_select "td small", text: "3002"
  end


  test "filters CPC campaigns by selected states" do
    archived = RawOzon::AdUnit.create!(account: @account, external_id: "archived", unit_type: "cpc_campaign",
      title: "Archived campaign", state: "CAMPAIGN_STATE_ARCHIVED", billing_model: "cpc",
      raw_json: {}, synced_at: Time.current)

    get reports_ozon_ads_cpc_path, params: { store_id: @store.id, statuses: ["CAMPAIGN_STATE_ARCHIVED"] }

    assert_response :success
    assert_select "td", text: "Archived campaign"
    assert_select "td", text: "CPC Test", count: 0
  ensure
    archived&.destroy!
  end

  test "renders CPC SKU detail without calling Ozon" do
    get reports_ozon_ads_cpc_detail_path("101"),
      params: { store_id: @store.id, from_date: Date.yesterday, to_date: Date.yesterday },
      headers: { "Turbo-Frame" => "ozon_ads_drawer" }
    assert_response :success
    assert_select "turbo-frame#ozon_ads_drawer"
    assert_select "#ozon-ads-drawer-title", text: "CPC Test"
    assert_select "[style*='--overlay-drawer-width: min(90vw, calc(100vw - 24px))']"
    assert_select ".ozon-ads-drawer-content .ozon-ads-summary .ozon-ads-summary__item", count: 6
    assert_select "td strong", text: @ec_sku.sku_code
    assert_select "td small", text: "3001"
    assert_select "td", text: /500\.00 ₽/
  end
end
