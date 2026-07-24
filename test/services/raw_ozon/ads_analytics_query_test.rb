require "test_helper"
require "securerandom"

class RawOzonAdsAnalyticsQueryTest < ActiveSupport::TestCase
  setup do
    token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(client_id: "ads-query-#{token}", api_key: token, company_type: "small")
    @date = Date.new(2026, 7, 22)
    @cpc = create_unit("cpc", "cpc_campaign")
    @selected = create_unit("selected", "cpo_selected")
    @all = create_unit("all", "cpo_all")
    RawOzon::AdUnitProduct.create!(ad_unit: @cpc, ozon_sku_id: "cpc-sku", is_current: true,
      raw_json: {}, synced_at: Time.current)
    RawOzon::AdUnitProduct.create!(ad_unit: @selected, ozon_sku_id: "sku-1", is_current: true,
      raw_json: {}, synced_at: Time.current)

    create_daily(@cpc, "cpc", impressions: 100, clicks: 10, cart_additions: 3, spend: 50, ad_revenue: 500, orders_count: 5)
    create_daily(@selected, "cpo", impressions: 20, clicks: 4, spend: 200, ad_revenue: 900, orders_count: 9)
    create_daily(@all, "cpo", impressions: 300, clicks: 30, cart_additions: 6, spend: 300, ad_revenue: 0, orders_count: 0)
    create_daily(@all, "cpo_all_report", spend: 300, ad_revenue: 3_000, orders_count: 30)
    RawOzon::AdSkuDailyStat.create!(account: @account, ad_unit: @selected, ozon_sku_id: "sku-1",
      stat_date: @date, cost_model: "cpo", spend: 200, ad_revenue: 2_000, orders_count: 20,
      raw_json: {}, synced_at: Time.current)
    RawOzon::AdSkuDailyStat.create!(account: @account, ad_unit: @selected, ozon_sku_id: "sku-1",
      stat_date: @date, cost_model: "combo", spend: 70, ad_revenue: 700, orders_count: 7,
      raw_json: {}, synced_at: Time.current)
  end

  teardown do
    RawOzon::AdSkuDailyStat.where(account_id: @account.id).delete_all
    RawOzon::AdDailyStat.where(account_id: @account.id).delete_all
    RawOzon::AdUnitProduct.where(ad_unit_id: RawOzon::AdUnit.where(account_id: @account.id)).delete_all
    RawOzon::AdUnit.where(account_id: @account.id).delete_all
    @account.destroy!
  end

  test "merges overview metrics from the matching report source without double counting" do
    rows = RawOzon::Ads::AnalyticsQuery.new(account: @account, from_date: @date, to_date: @date).overview_rows

    cpc = rows.find { |row| row[:unit_type] == "cpc_campaign" }
    assert_equal [50, 500, 5, 100, 10], values(cpc)

    selected = rows.find { |row| row[:unit_type] == "cpo_selected" }
    assert_equal [200, 2_700, 27, 0, 0], values(selected)

    _unit, selected_products = RawOzon::Ads::AnalyticsQuery.new(
      account: @account, from_date: @date, to_date: @date
    ).cpo_selected_rows
    assert_equal [270, 2_700, 27, 0, 0], values(selected_products.sole)

    all = rows.find { |row| row[:unit_type] == "cpo_all" }
    assert_equal [300, 3_000, 30, 300, 30], values(all)
  end

  test "filters CPC campaigns by multiple states" do
    @cpc.update!(state: "CAMPAIGN_STATE_RUNNING")
    inactive = create_unit("inactive", "cpc_campaign")
    inactive.update!(state: "CAMPAIGN_STATE_INACTIVE")
    archived = create_unit("archived", "cpc_campaign")
    archived.update!(state: "CAMPAIGN_STATE_ARCHIVED")

    rows = RawOzon::Ads::AnalyticsQuery.new(account: @account, from_date: @date, to_date: @date)
      .cpc_rows(states: %w[CAMPAIGN_STATE_RUNNING CAMPAIGN_STATE_INACTIVE])

    assert_equal %w[cpc inactive], rows.map { |row| row[:unit].external_id }.sort
  end

  test "uses complete campaign metrics for a CPC campaign with one product" do
    rows = RawOzon::Ads::AnalyticsQuery.new(account: @account, from_date: @date, to_date: @date).cpc_detail(@cpc)

    assert_equal [50, 500, 5, 100, 10], values(rows.sole)
  end

  test "prefers historical CPC report when the recent endpoint overlaps the same SKU date" do
    unit = create_unit("multi", "cpc_campaign")
    %w[sku-a sku-b].each do |sku|
      RawOzon::AdUnitProduct.create!(ad_unit: unit, ozon_sku_id: sku, is_current: true,
        raw_json: {}, synced_at: Time.current)
    end
    %w[cpc cpc_history].each_with_index do |cost_model, index|
      RawOzon::AdSkuDailyStat.create!(account: @account, ad_unit: unit, ozon_sku_id: "sku-a",
        stat_date: @date, cost_model: cost_model, spend: index.zero? ? 50 : 60,
        raw_json: {}, synced_at: Time.current)
    end

    rows = RawOzon::Ads::AnalyticsQuery.new(account: @account, from_date: @date, to_date: @date).cpc_detail(unit)

    assert_equal 60, rows.find { |row| row[:product].ozon_sku_id == "sku-a" }[:spend].to_i
  end

  test "uses deduplicated SKU statistics for CPC campaign cart additions" do
    %w[cpc cpc_history].each_with_index do |cost_model, index|
      RawOzon::AdSkuDailyStat.create!(account: @account, ad_unit: @cpc, ozon_sku_id: "cpc-sku",
        stat_date: @date, cost_model: cost_model, cart_additions: index.zero? ? 3 : 7,
        raw_json: {}, synced_at: Time.current)
    end

    row = RawOzon::Ads::AnalyticsQuery.new(account: @account, from_date: @date, to_date: @date).cpc_rows.sole

    assert_equal 7, row[:cart_additions].to_i
    assert_equal 5, row[:avg_cpc].to_i
  end

  private

  def create_unit(external_id, unit_type)
    RawOzon::AdUnit.create!(account: @account, external_id: external_id, unit_type: unit_type,
      billing_model: unit_type == "cpc_campaign" ? "cpc" : "cpo", raw_json: {}, synced_at: Time.current)
  end

  def create_daily(unit, cost_model, attributes)
    RawOzon::AdDailyStat.create!({ account: @account, ad_unit: unit, stat_date: @date, cost_model: cost_model,
      raw_json: {}, synced_at: Time.current }.merge(attributes))
  end

  def values(row)
    %i[spend ad_revenue orders_count impressions clicks].map { |metric| row.fetch(metric).to_i }
  end
end
