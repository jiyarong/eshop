require "test_helper"
require "securerandom"

class Reports::WbAdsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(6)
    @user = create_user_with_roles("wb-ads-#{@token}@example.com", "manager")
    sign_in @user
    @store = Ec::Store.create!(
      platform: "wb",
      store_name: "WB Ads #{@token}",
      company_type: "small",
      wb_api_token: "token-#{@token}",
      is_active: true
    )
    @campaign = RawWb::AdvCampaign.create!(
      store: @store,
      advert_id: 98_765_432,
      campaign_type: 9,
      status: 9,
      name: "WB Campaign #{@token}",
      payment_type: "cpm",
      bid_type: "manual",
      currency: "RUB",
      placements: { "search" => true, "recommendations" => true },
      is_current: true,
      raw_payload: {},
      synced_at: Time.current
    )
    @product = RawWb::AdvCampaignProduct.create!(
      campaign: @campaign,
      nm_id: 860_790_648,
      search_bid_kopecks: 82_900,
      recommendation_bid_kopecks: 34_000,
      is_current: true,
      raw_payload: {},
      synced_at: Time.current
    )
    RawWb::AdvBudgetSnapshot.create!(
      campaign: @campaign,
      total: 506,
      currency: "RUB",
      observed_at: Time.current,
      raw_payload: {}
    )
    @date = Date.new(2026, 7, 22)
    RawWb::AdvCampaignDailyStat.create!(
      campaign: @campaign,
      stat_date: @date,
      views: 1000,
      clicks: 50,
      add_to_cart: 10,
      orders: 2,
      ordered_units: 2,
      canceled: 1,
      spend: 500,
      revenue: 5000,
      currency: "RUB",
      raw_payload: {},
      synced_at: Time.current
    )
    RawWb::AdvProductDailyStat.create!(
      campaign: @campaign,
      stat_date: @date,
      app_type: -1,
      nm_id: @product.nm_id,
      product_name: "Test towel rail",
      views: 1000,
      clicks: 50,
      add_to_cart: 10,
      orders: 2,
      ordered_units: 2,
      canceled: 1,
      spend: 500,
      revenue: 5000,
      avg_position: 12,
      currency: "RUB",
      raw_payload: {},
      synced_at: Time.current
    )
    @attribution_campaign = RawWb::AdvCampaign.create!(
      store: @store,
      advert_id: 98_765_433,
      campaign_type: 9,
      status: 11,
      name: "Attribution Campaign #{@token}",
      payment_type: "cpm",
      bid_type: "manual",
      currency: "RUB",
      placements: {},
      is_current: true,
      raw_payload: {},
      synced_at: Time.current
    )
    RawWb::AdvProductDailyStat.create!(
      campaign: @attribution_campaign,
      stat_date: @date,
      app_type: -1,
      nm_id: @product.nm_id,
      product_name: "Test towel rail",
      orders: 1,
      ordered_units: 1,
      revenue: 300,
      currency: "RUB",
      raw_payload: {},
      synced_at: Time.current
    )
  end

  teardown do
    campaign_ids = RawWb::AdvCampaign.where(store_id: @store.id).select(:id)
    RawWb::AdvProductDailyStat.where(campaign_id: campaign_ids).delete_all
    RawWb::AdvCampaignDailyStat.where(campaign_id: campaign_ids).delete_all
    RawWb::AdvBudgetSnapshot.where(campaign_id: campaign_ids).delete_all
    RawWb::AdvCampaignProduct.where(campaign_id: campaign_ids).delete_all
    RawWb::AdvCampaign.where(store_id: @store.id).delete_all
    Ec::Store.where(id: @store.id).delete_all
    UserRole.where(user_id: @user.id).delete_all
    @user.destroy!
  end

  test "renders campaign view with shared date and store filters" do
    get reports_wb_ads_path, params: {
      store_id: @store.id,
      from_date: @date,
      to_date: @date
    }

    assert_response :success
    assert_select "h1", text: I18n.t("reports.wb_ads.title")
    assert_select "[data-controller='time-range-selector']", count: 1
    assert_select ".weekly-profit-filter-tag.is-active", text: @store.store_name
    assert_select ".wb-ads-view-switch__link.is-active", text: I18n.t("reports.wb_ads.views.campaigns")
    assert_select ".wb-ads-summary__item", count: 5
    assert_select "a[data-turbo-frame='wb_ads_drawer']", text: @campaign.name
    assert_select ".status-pill.is-active", text: I18n.t("reports.wb_ads.statuses.9")
    assert_select "td", text: /506\.00 ₽/
    assert_select "th", text: I18n.t("reports.wb_ads.metrics.drr")
    assert_select "turbo-frame#wb_ads_drawer", count: 1
  end

  test "renders product view with WB product metrics" do
    get reports_wb_ads_path, params: {
      store_id: @store.id,
      from_date: @date,
      to_date: @date,
      view: "products",
      q: @product.nm_id
    }

    assert_response :success
    assert_select ".wb-ads-view-switch__link.is-active", text: I18n.t("reports.wb_ads.views.products")
    assert_select "td strong", text: "Test towel rail"
    assert_select "td small", text: /#{@product.nm_id}/
    assert_select "td small", text: /#{I18n.t('reports.wb_ads.fields.campaign_count', count: 1)}/
    assert_select "button[data-action='table-row-expander#toggle'][aria-expanded='false']", count: 1
    assert_select "turbo-frame[data-lazy-src]", count: 1
    assert_select "th", text: I18n.t("reports.wb_ads.metrics.avg_position")
    assert_select "th", text: I18n.t("reports.wb_ads.metrics.cpm")
    assert_select "th", text: I18n.t("reports.wb_ads.metrics.canceled")
  end

  test "renders configured campaigns and other attribution for an expanded product" do
    get reports_wb_ads_product_campaigns_path(@product.nm_id),
      params: { store_id: @store.id, from_date: @date, to_date: @date },
      headers: { "Turbo-Frame" => "wb_ads_product_#{@product.nm_id}_campaigns" }

    assert_response :success
    assert_select "turbo-frame#wb_ads_product_#{@product.nm_id}_campaigns"
    assert_select "a[data-turbo-frame='wb_ads_drawer']", text: @campaign.name
    assert_select "td", text: I18n.t("reports.wb_ads.other_attribution")
    assert_select "td", text: @attribution_campaign.name, count: 0
  end

  test "renders campaign detail in a Turbo drawer without calling WB" do
    get reports_wb_ads_campaign_path(@campaign.advert_id),
      params: { store_id: @store.id, from_date: @date, to_date: @date },
      headers: { "Turbo-Frame" => "wb_ads_drawer" }

    assert_response :success
    assert_select "turbo-frame#wb_ads_drawer"
    assert_select "#wb-ads-drawer-title", text: @campaign.name
    assert_select ".wb-ads-drawer-content .wb-ads-summary__item", count: 5
    assert_select "td strong", text: "Test towel rail"
    assert_select "td", text: /829\.00 ₽/
  end

  test "returns the filtered report as JSON" do
    get reports_wb_ads_path(format: :json), params: {
      store_id: @store.id,
      from_date: @date,
      to_date: @date,
      view: "products"
    }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal @store.id, payload.dig("store", "id")
    assert_equal "products", payload["view"]
    assert_equal @product.nm_id, payload.dig("rows", 0, "nm_id")
  end
end
