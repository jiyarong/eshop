require "test_helper"

class ErpAI::V2::AdvertisingContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "ADS-CONTEXT-#{@token}", product_name: "Ads context")
    @wb_account = RawWb::SellerAccount.create!(
      name: "Ads WB #{@token}", api_token: "wb-#{@token}", company_type: :small
    )
    @wb_store = Ec::Store.create!(
      platform: "wb", store_name: "Ads WB #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id
    )
    @wb_product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "71001")
    @wb_campaign = RawWb::AdvCampaign.create!(
      store: @wb_store, advert_id: 71_001, status: 11, is_current: false,
      name: "Closed WB", currency: "RUB", placements: {}, raw_payload: {}, synced_at: Time.current
    )
    @wb_campaign_product = RawWb::AdvCampaignProduct.create!(
      campaign: @wb_campaign, nm_id: 71_001, is_current: false, raw_payload: {}, synced_at: Time.current
    )

    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Ads Ozon #{@token}", client_id: "ozon-#{@token}", api_key: "key-#{@token}", company_type: :small
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon", store_name: "Ads Ozon #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id
    )
    @ozon_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZON-ADS-#{@token}", platform_sku_id: "81001"
    )
    @ozon_unit = RawOzon::AdUnit.create!(
      account: @ozon_account, external_id: "archived-#{@token}", unit_type: "cpc_campaign",
      state: "CAMPAIGN_STATE_ARCHIVED", raw_json: {}, synced_at: Time.current
    )
    @ozon_unit_product = RawOzon::AdUnitProduct.create!(
      ad_unit: @ozon_unit, ozon_sku_id: "81001", is_current: false, raw_json: {}, synced_at: Time.current
    )
  end

  teardown do
    RawOzon::AdSkuDailyStat.where(account_id: @ozon_account&.id).delete_all
    RawOzon::AdUnitProduct.where(ad_unit_id: @ozon_unit&.id).delete_all
    RawOzon::AdUnit.where(id: @ozon_unit&.id).delete_all
    RawWb::AdvProductDailyStat.where(campaign_id: @wb_campaign&.id).delete_all
    RawWb::AdvCampaignProduct.where(campaign_id: @wb_campaign&.id).delete_all
    RawWb::AdvCampaign.where(id: @wb_campaign&.id).delete_all
    Ec::SkuProduct.where(id: [@wb_product&.id, @ozon_product&.id]).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id]).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "keeps closed campaign history and prefers Ozon CPC history rows" do
    first_week = Date.new(2026, 8, 3)
    RawWb::AdvProductDailyStat.create!(
      campaign: @wb_campaign, stat_date: first_week, app_type: -1, nm_id: 71_001,
      views: 1_000, clicks: 50, add_to_cart: 10, orders: 2, ordered_units: 2,
      spend: 500, revenue: 5_000, avg_position: 12, currency: "RUB", raw_payload: {}, synced_at: Time.current
    )
    %w[cpc cpc_history].each_with_index do |cost_model, index|
      RawOzon::AdSkuDailyStat.create!(
        account: @ozon_account, ad_unit: @ozon_unit, ozon_sku_id: "81001", stat_date: first_week,
        cost_model:, impressions: index.zero? ? 100 : 120, clicks: index.zero? ? 10 : 12,
        cart_additions: index.zero? ? 3 : 4, orders_count: index.zero? ? 2 : 3,
        spend: index.zero? ? 50 : 60, ad_revenue: index.zero? ? 500 : 600,
        raw_json: {}, synced_at: Time.current
      )
    end

    result = ErpAI::V2::AdvertisingContext.new(
      sku: @sku, period_from: first_week, period_to: Date.new(2026, 8, 16), today: Date.new(2026, 8, 12)
    ).call

    assert_equal 2, result.size
    assert_equal false, result.first.fetch(:is_partial)
    assert_equal true, result.last.fetch(:is_partial)
    wb = result.first.fetch(:stores).find { |store| store[:platform] == "wb" }.fetch(:data).sole
    assert_equal "available", wb.fetch(:data_status)
    assert_equal 500, wb.fetch(:spend).to_i
    assert_equal 10, wb.fetch(:drr_pct).to_i
    ozon = result.first.fetch(:stores).find { |store| store[:platform] == "ozon" }.fetch(:data).sole
    assert_equal 60, ozon.fetch(:spend).to_i
    assert_equal 120, ozon.fetch(:impressions)
    assert_equal 1, ozon.fetch(:campaign_count)
    assert_equal "no_records", result.last.fetch(:stores).first.fetch(:data_status)
  end

  test "limits report queries to the requested stores" do
    result = ErpAI::V2::AdvertisingContext.new(
      sku: @sku,
      period_from: Date.new(2026, 8, 3),
      period_to: Date.new(2026, 8, 9),
      store_ids: [ @ozon_store.id ]
    ).call

    assert_equal [ @ozon_store.id ], result.sole.fetch(:stores).pluck(:store_id)
  end

  test "can mark the current Sunday as partial for compact marketing contexts" do
    result = ErpAI::V2::AdvertisingContext.new(
      sku: @sku,
      period_from: Date.new(2026, 8, 17),
      period_to: Date.new(2026, 8, 23),
      today: Date.new(2026, 8, 23),
      partial_on_today: true
    ).call

    assert_equal true, result.sole.fetch(:is_partial)
  end

  test "quarantines money when a WB record has a missing currency" do
    week = Date.new(2026, 8, 3)
    RawWb::AdvProductDailyStat.create!(
      campaign: @wb_campaign, stat_date: week, app_type: -1, nm_id: 71_001,
      views: 20, clicks: 2, add_to_cart: 2, orders: 2, ordered_units: 2,
      spend: 10, revenue: 100, avg_position: 10, currency: "RUB", raw_payload: {}, synced_at: Time.current
    )
    RawWb::AdvProductDailyStat.create!(
      campaign: @wb_campaign, stat_date: week + 1.day, app_type: -1, nm_id: 71_001,
      views: 10, clicks: 1, add_to_cart: 1, orders: 1, ordered_units: 1,
      spend: 5, revenue: 50, avg_position: 10, currency: nil, raw_payload: {}, synced_at: Time.current
    )

    row = ErpAI::V2::AdvertisingContext.new(
      sku: @sku, period_from: week, period_to: week + 6.days, strict_nulls: true
    ).call.sole.fetch(:stores).find { |store| store[:platform] == "wb" }.fetch(:data).sole

    assert_equal "MIXED", row.fetch(:currency)
    (ErpAI::V2::AdvertisingContext::MONEY_METRICS + ErpAI::V2::AdvertisingContext::MONEY_DERIVED_METRICS).each do |metric|
      assert_nil row.fetch(metric), metric
    end
    assert_equal 30, row.fetch(:impressions)
  end

  test "preserves NULL Ozon metrics instead of treating them as zero" do
    week = Date.new(2026, 8, 3)
    RawOzon::AdSkuDailyStat.create!(
      account: @ozon_account, ad_unit: @ozon_unit, ozon_sku_id: "81001", stat_date: week,
      cost_model: "cpc", impressions: nil, clicks: 0, cart_additions: 0, orders_count: 0,
      model_orders_count: nil, spend: nil, ad_revenue: nil, model_revenue: nil,
      raw_json: {}, synced_at: Time.current
    )

    row = ErpAI::V2::AdvertisingContext.new(
      sku: @sku, period_from: week, period_to: week + 6.days, strict_nulls: true
    ).call.sole.fetch(:stores).find { |store| store[:platform] == "ozon" }.fetch(:data).sole

    assert_equal "available", row.fetch(:data_status)
    assert_nil row.fetch(:impressions)
    assert_equal 0, row.fetch(:clicks)
    assert_nil row.fetch(:spend)
    assert_nil row.fetch(:attributed_revenue)
    assert_nil row.fetch(:roas)
  end
end
