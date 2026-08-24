require "test_helper"

class Ec::SkuAdvertisingDiagnosisQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @date = Date.new(2026, 8, 3)
    @sku = Ec::Sku.create!(sku_code: "AD-DIAG-#{@token}", product_name: "Advertising diagnosis", is_active: true)
    @sku.marketing_states.create!(grade: "A", stage: "mat", effective_at: 1.day.ago)
    @account = RawOzon::SellerAccount.create!(client_id: "ad-diag-#{@token}", api_key: @token, company_type: "small")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Ad diagnosis #{@token}", company_type: "small",
      is_active: true, ozon_raw_account_id: @account.id)
    @product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @store, product_id: "product-#{@token}", platform_sku_id: "12345")
    @unit = RawOzon::AdUnit.create!(account: @account, external_id: "campaign-#{@token}", unit_type: "cpc_campaign",
      billing_model: "cpc", state: "CAMPAIGN_STATE_RUNNING", raw_json: {}, synced_at: Time.current)
    RawOzon::AdUnitProduct.create!(ad_unit: @unit, ozon_sku_id: "12345", is_current: true, raw_json: {}, synced_at: Time.current)
  end

  teardown do
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all
    RawOzon::SalesFunnelDaily.where(account_id: @account&.id).delete_all
    RawOzon::AdSkuDailyStat.where(account_id: @account&.id).delete_all
    RawOzon::AdUnitProduct.where(ad_unit_id: @unit&.id).delete_all
    RawOzon::AdUnit.where(id: @unit&.id).delete_all
    Ec::SkuProduct.where(id: @product&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::SkuMarketingState.where(sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    RawOzon::SellerAccount.where(id: @account&.id).delete_all
  end

  test "returns listing advertising and overall funnel metrics without double counting CPC sources" do
    create_ad_stat("cpc", spend: 50, impressions: 100, clicks: 10, cart_additions: 2, orders_count: 1, ad_revenue: 500)
    create_ad_stat("cpc_history", spend: 60, impressions: 120, clicks: 12, cart_additions: 3, orders_count: 2, ad_revenue: 600)
    RawOzon::SalesFunnelDaily.create!(account: @account, sku: 12_345, stat_date: @date,
      hits_view: 200, hits_tocart: 10, ordered_units: 5, revenue: 1_000, raw_json: {}, synced_at: Time.current)
    Ec::Snapshot.create!(sku: @sku, snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: @date, content: { overview: { out_of_stock: false } })

    result = query.call
    listing = result.fetch(:listings).sole
    day = listing.fetch(:daily).sole

    assert_equal "ozon", listing.fetch(:platform)
    assert_equal 1, listing.dig(:campaign_summary, :running)
    assert_equal 60.0, day.dig(:advertising, :spend)
    assert_equal 12.0, day.dig(:advertising, :clicks)
    assert_equal 600.0, day.dig(:advertising, :revenue)
    assert_equal 60.0, day.fetch(:attributed_revenue_share_pct)
    assert_equal false, day.fetch(:inventory_constrained)
    assert_equal @date, listing.dig(:data_freshness, :advertising, :latest_stat_date)
    assert_equal 1, listing.dig(:data_freshness, :advertising, :covered_dates)
    assert_equal @date, listing.dig(:data_freshness, :overall_funnel, :latest_stat_date)
    assert_equal 1, listing.dig(:data_freshness, :overall_funnel, :covered_dates)
  end

  test "rejects ranges longer than thirty five days" do
    assert_raises(ArgumentError) do
      Ec::SkuAdvertisingDiagnosisQuery.new(sku: @sku, from_date: @date - 35.days, to_date: @date)
    end
  end

  private

  def query
    Ec::SkuAdvertisingDiagnosisQuery.new(sku: @sku, from_date: @date, to_date: @date)
  end

  def create_ad_stat(cost_model, attributes)
    RawOzon::AdSkuDailyStat.create!({ account: @account, ad_unit: @unit, ozon_sku_id: "12345",
      stat_date: @date, cost_model: cost_model, raw_json: {}, synced_at: Time.current }.merge(attributes))
  end
end
