require "test_helper"

class ErpAI::V2::SearchTermsContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "SEARCH-CONTEXT-#{@token}", product_name: "Search context")
    @wb_account = RawWb::SellerAccount.create!(name: "Search WB #{@token}", api_token: "wb-#{@token}", company_type: :small)
    @ozon_account = RawOzon::SellerAccount.create!(company_name: "Search Ozon #{@token}", client_id: "oz-#{@token}", api_key: "key-#{@token}", company_type: :small)
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "Search WB #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Search Ozon #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id)
    @wb_product = Ec::SkuProduct.create!(sku: @sku, store: @wb_store, product_id: "71001")
    @ozon_product = Ec::SkuProduct.create!(sku: @sku, store: @ozon_store, product_id: "OZON-#{@token}", platform_sku_id: "81001")
  end

  teardown do
    RawWb::AnalyticsSearchTerm.where(account_id: @wb_account&.id).delete_all
    RawWb::SearchReportProduct.where(account_id: @wb_account&.id).delete_all
    RawOzon::ProductQueryDetail.where(account_id: @ozon_account&.id).delete_all
    RawOzon::ProductQuery.where(account_id: @ozon_account&.id).delete_all
    Ec::SkuProduct.where(id: [@wb_product&.id, @ozon_product&.id]).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id]).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "returns only first-level weekly SKU summaries for WB and Ozon" do
    week_start = Date.new(2026, 8, 3)
    week_end = Date.new(2026, 8, 9)
    RawWb::SearchReportProduct.create!(
      account: @wb_account, period_from: week_start, period_to: week_end, nm_id: 71_001,
      avg_position: 20, open_card: 100, add_to_cart: 20, open_to_cart: 20,
      orders: 5, cart_to_order: 25, visibility: 60, raw_json: { "large" => true }, synced_at: Time.current
    )
    RawWb::AnalyticsSearchTerm.create!(
      account: @wb_account, period_from: week_start, period_to: week_end, keyword: "hidden detail",
      nm_id: 71_001, top_order_by: "openCard", top_order_rank: 1, frequency: 1_000,
      raw_json: { "large" => true }, synced_at: Time.current
    )
    RawOzon::ProductQuery.create!(
      account: @ozon_account, period_from: week_start, period_to: week_end, sku: 81_001,
      unique_search_users: 200, unique_view_users: 50, position: 8, view_conversion: 25,
      gmv: 5_000, currency: "RUB", synced_at: Time.current
    )
    RawOzon::ProductQueryDetail.create!(
      account: @ozon_account, period_from: week_start, period_to: week_end, sku: 81_001,
      query: "hidden Ozon detail", top_order_by: "BY_SEARCHES", unique_search_users: 9_999,
      synced_at: Time.current
    )

    result = ErpAI::V2::SearchTermsContext.new(
      sku: @sku, period_from: week_start, period_to: Date.new(2026, 8, 16), today: Date.new(2026, 8, 12)
    ).call

    assert_equal 2, result.size
    assert_equal false, result.first.fetch(:is_partial)
    assert_equal true, result.last.fetch(:is_partial)
    wb = result.first.fetch(:stores).find { |store| store[:platform] == "wb" }.fetch(:data).sole
    assert_equal({ term_count: 1, views: 100, add_to_cart: 20, orders: 5 }, wb.slice(:term_count, :views, :add_to_cart, :orders))
    assert_not wb.key?(:keyword)
    ozon = result.first.fetch(:stores).find { |store| store[:platform] == "ozon" }.fetch(:data).sole
    assert_equal({ search_volume: 200, views: 50, revenue: 5_000.to_d }, ozon.slice(:search_volume, :views, :revenue))
    assert_not ozon.key?(:query)
    assert_equal "no_records", result.last.fetch(:stores).first.fetch(:data_status)
  end

  test "limits report queries to the requested stores" do
    result = ErpAI::V2::SearchTermsContext.new(
      sku: @sku,
      period_from: Date.new(2026, 8, 3),
      period_to: Date.new(2026, 8, 9),
      store_ids: [ @wb_store.id ]
    ).call

    assert_equal [ @wb_store.id ], result.sole.fetch(:stores).pluck(:store_id)
  end

  test "can mark the current Sunday as partial for compact marketing contexts" do
    result = ErpAI::V2::SearchTermsContext.new(
      sku: @sku,
      period_from: Date.new(2026, 8, 17),
      period_to: Date.new(2026, 8, 23),
      today: Date.new(2026, 8, 23),
      partial_on_today: true
    ).call

    assert_equal true, result.sole.fetch(:is_partial)
  end
end
