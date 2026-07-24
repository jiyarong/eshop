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
      title: "CPC Test", state: "CAMPAIGN_STATE_RUNNING", billing_model: "cpc",
      placement: ["PLACEMENT_SEARCH_AND_CATEGORY"], raw_json: { "updatedAt" => "2026-07-14T10:30:00Z" },
      synced_at: Time.current)
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
    RawOzon::AdSkuDailyStat.create!(account: @account, ad_unit: @cpo, ozon_sku_id: "3002", stat_date: Date.yesterday,
      cost_model: "combo", orders_count: 2, ad_revenue: 3000, spend: 300, raw_json: {}, synced_at: Time.current)
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
    get reports_ozon_ads_cpc_path,
      params: { store_id: @store.id, q: "3001", from_date: Date.yesterday, to_date: Date.yesterday }
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
    assert_select ".ozon-ads-store-filter.weekly-profit-filter-block .weekly-profit-filter-tag", minimum: 1
    assert_select "th", text: I18n.t("reports.ozon_ads.fields.placement")
    assert_select "th", text: I18n.t("reports.ozon_ads.metrics.cart_additions")
    assert_select "th", text: I18n.t("reports.ozon_ads.metrics.avg_cpc")
    assert_select "th", text: I18n.t("reports.ozon_ads.fields.change_date")
    assert_select "td", text: I18n.t("reports.ozon_ads.placements.PLACEMENT_SEARCH_AND_CATEGORY")
    assert_select "td > span", text: "3"
    assert_select "td", text: /50\.00 ₽/
    assert_select "td", text: "2026-07-14"
    assert_select "turbo-frame#ozon_ads_drawer", count: 1

    sign_in @user
    get reports_ozon_ads_cpo_selected_path,
      params: { store_id: @store.id, from_date: Date.yesterday, to_date: Date.yesterday }
    assert_response :success
    assert_select "td strong", text: @cpo_ec_sku.sku_code
    assert_select "td small", text: "3002"
    assert_select "td", text: /5,000\.00 ₽/
    assert_select "td > span", text: "3"
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

  test "defaults promotion reports to the last completed natural week" do
    travel_to Time.zone.local(2026, 7, 24, 12) do
      get reports_ozon_ads_cpc_path, params: { store_id: @store.id }

      assert_response :success
      assert_select "input[name='from_date'][value='2026-07-13']"
      assert_select "input[name='to_date'][value='2026-07-19']"
    end
  end

  test "renders comparisons against the immediately preceding equal period" do
    current_date = Date.new(2026, 7, 14)
    previous_date = current_date - 1.day
    RawOzon::AdDailyStat.create!(account: @account, ad_unit: @cpc, stat_date: current_date, cost_model: "cpc",
      impressions: 200, clicks: 20, orders_count: 4, ad_revenue: 1000, spend: 200,
      raw_json: {}, synced_at: Time.current)
    RawOzon::AdDailyStat.create!(account: @account, ad_unit: @cpc, stat_date: previous_date, cost_model: "cpc",
      impressions: 100, clicks: 10, orders_count: 2, ad_revenue: 500, spend: 100,
      raw_json: {}, synced_at: Time.current)

    get reports_ozon_ads_cpc_path,
      params: { store_id: @store.id, from_date: current_date, to_date: current_date }

    assert_response :success
    assert_select ".weekly-profit-comparison-note", text: /2026-07-13/
    assert_select ".ozon-ads-summary__item .weekly-profit-comparison-trend.is-negative", text: /100\.00%/, minimum: 1
    assert_select ".ozon-ads-summary__item .weekly-profit-comparison-trend.is-positive", text: /100\.00%/, minimum: 1
    assert_select "tbody .weekly-profit-table-comparison.is-negative", text: /100\.00%/, minimum: 1
  ensure
    RawOzon::AdDailyStat.where(account_id: @account.id, stat_date: [current_date, previous_date]).delete_all
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
