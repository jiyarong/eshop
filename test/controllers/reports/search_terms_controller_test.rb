require "test_helper"

class Reports::SearchTermsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("search-terms-#{@token.downcase}@example.com", "manager")
    sign_in @user
    @wb_account = RawWb::SellerAccount.create!(
      name: "Search WB #{@token}", api_token: "wb-#{@token}", company_type: :small, is_active: true
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Search Ozon #{@token}", client_id: "ozon-#{@token}", api_key: "key-#{@token}",
      company_type: :small, is_active: true
    )
    @wb_store = Ec::Store.create!(
      platform: "wb", store_name: "Search WB #{@token}", company_type: "small",
      wb_raw_account_id: @wb_account.id, is_active: true
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon", store_name: "Search Ozon #{@token}", company_type: "small",
      ozon_raw_account_id: @ozon_account.id, is_active: true
    )
    @sku = Ec::Sku.create!(sku_code: "SEARCH-#{@token}", product_name: "搜索词测试商品")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "71001")
    Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZON-#{@token}", platform_sku_id: "81001"
    )
    @period_from = Date.new(2026, 8, 3)
    @period_to = Date.new(2026, 8, 9)
  end

  teardown do
    RawWb::AnalyticsSearchTerm.where(account_id: @wb_account.id).delete_all
    RawWb::SearchReportProduct.where(account_id: @wb_account.id).delete_all
    RawOzon::ProductQueryDetail.where(account_id: @ozon_account.id).delete_all
    RawOzon::ProductQuery.where(account_id: @ozon_account.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku.sku_code).delete_all
    Ec::Store.where(id: [@wb_store.id, @ozon_store.id]).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    @wb_account.destroy!
    @ozon_account.destroy!
    UserRole.where(user_id: @user.id).delete_all
    @user.destroy!
  end

  test "renders WB SKU rows from the natural-week search term table" do
    create_wb_term
    create_wb_summary
    create_wb_term(period_from: @period_from - 1.week, period_to: @period_to - 1.week,
      frequency: 50, avg_position: 40, open_card: 10, add_to_cart: 4, orders: 1)
    create_wb_summary(period_from: @period_from - 1.week, period_to: @period_to - 1.week,
      avg_position: 39, open_card: 31, add_to_cart: 4, orders: 1)

    row = SearchTermReports::Query.new(
      platform: "wb", store: @wb_store, period_from: @period_from, period_to: @period_to
    ).rows.sole
    assert_equal @sku.sku_code, row[:sku_code]
    assert_equal 33, row[:avg_position].to_i
    assert_equal 62, row[:views]
    assert_equal 8, row[:add_to_cart]
    assert_equal 13, row[:cart_conversion].to_i
    assert_equal 1, row[:orders]
    assert_equal 13, row[:conversion].to_i
    assert_equal 50, row[:visibility].to_i

    get reports_search_terms_path, params: period_params.merge(platform: "wb", store_id: @wb_store.id)

    assert_response :success
    assert_select "h1", I18n.t("reports.search_terms.title")
    assert_select ".search-terms-platform-tabs", count: 0
    assert_select ".search-terms-store-filter .weekly-profit-filter-tag", text: "WB · #{@wb_store.store_name}"
    assert_select ".search-terms-store-filter .weekly-profit-filter-tag", text: "Ozon · #{@ozon_store.store_name}"
    assert_select ".search-terms-store-filter .weekly-profit-filter-tag.is-active", text: "WB · #{@wb_store.store_name}"
    assert_select "[data-controller='time-range-selector']"
    assert_select "[data-controller='spu-sku-filter']"
    assert_select "th", I18n.t("reports.search_terms.columns.wb.add_to_cart")
    assert_select "th", I18n.t("reports.search_terms.columns.wb.cart_conversion")
    assert_select "th", I18n.t("reports.search_terms.columns.wb.visibility")
    assert_select "tr.search-terms-sku-row", 1
    assert_select "a[data-turbo-frame='sku_detail_drawer']", text: @sku.sku_code
    assert_select "turbo-frame[data-lazy-src*=?]", "/reports/search_terms/#{@sku.sku_code}/terms", 1
    assert_select ".weekly-profit-table-comparison.is-positive", text: "↑ 100%", minimum: 1
    assert_select ".weekly-profit-table-comparison.is-positive", text: "提升 6 位"
  end

  test "defaults to the previous complete natural week" do
    get reports_search_terms_path, params: { platform: "wb", store_id: @wb_store.id }

    monday = Date.current.beginning_of_week(:monday)
    assert_response :success
    assert_select "input[name='from_date'][value=?]", (monday - 1.week).iso8601
    assert_select "input[name='to_date'][value=?]", (monday - 1.day).iso8601
  end

  test "lazy-loads WB terms for an expanded SKU" do
    create_wb_term
    create_wb_term(period_from: @period_from - 1.week, period_to: @period_to - 1.week,
      frequency: 50, avg_position: 40, open_card: 10, add_to_cart: 4, orders: 1)
    create_wb_term(keyword: "старый запрос", period_from: @period_from - 1.week, period_to: @period_to - 1.week)
    create_wb_term(keyword: "новый запрос", frequency: 30)

    get reports_search_term_details_path(@sku.sku_code), params: period_params.merge(
      platform: "wb", store_id: @wb_store.id
    ), headers: { "Turbo-Frame" => "search_terms_wb_ec_sku_#{@sku.id}" }

    assert_response :success
    assert_select "turbo-frame#search_terms_wb_ec_sku_#{@sku.id}"
    assert_select "td strong", text: "полотенцесушитель"
    assert_select ".weekly-profit-table-comparison.is-positive", text: "提升 6 位"
    assert_select ".status-pill.is-active", text: I18n.t("reports.search_terms.comparison.lifecycle.new.wb")
    assert_select ".status-pill.is-muted", text: I18n.t("reports.search_terms.comparison.lifecycle.lost.wb")
    assert_select "tr.search-terms-detail-table__lost td strong", text: "старый запрос"
  end

  test "renders Ozon SKU summary and Top 15 term columns" do
    RawOzon::ProductQuery.create!(
      account: @ozon_account, period_from: @period_from, period_to: @period_to, sku: 81_001,
      offer_id: "OZON-#{@token}", name: "搜索词测试商品", unique_search_users: 100,
      unique_view_users: 25, position: 8.5, view_conversion: 25, gmv: 1_200, currency: "RUB",
      synced_at: Time.current
    )
    RawOzon::ProductQueryDetail.create!(
      account: @ozon_account, period_from: @period_from, period_to: @period_to, sku: 81_001,
      query: "полотенцесушитель", unique_search_users: 80, unique_view_users: 20,
      position: 7.5, view_conversion: 25, order_count: 3, gmv: 900, currency: "RUB",
      synced_at: Time.current
    )

    get reports_search_terms_path, params: period_params.merge(platform: "ozon", store_id: @ozon_store.id)

    assert_response :success
    assert_select "tr.search-terms-sku-row", 1
    assert_select "th", I18n.t("reports.search_terms.columns.ozon.search_volume")
    assert_select "th", I18n.t("reports.search_terms.columns.ozon.revenue")
    assert_select "th", { text: I18n.t("reports.search_terms.columns.wb.add_to_cart"), count: 0 }
  end

  test "does not show data for a period that is not a complete natural week" do
    create_wb_term

    get reports_search_terms_path, params: {
      platform: "wb", store_id: @wb_store.id, from_date: "2026-08-04", to_date: "2026-08-09"
    }

    assert_response :success
    assert_select ".search-terms-period-warning", text: /完整自然周/
    assert_select "tr.search-terms-sku-row", 0
  end

  private

  def period_params
    { from_date: @period_from.iso8601, to_date: @period_to.iso8601 }
  end

  def create_wb_term(keyword: "полотенцесушитель", period_from: @period_from, period_to: @period_to,
    frequency: 100, avg_position: 34, open_card: 20, add_to_cart: 8, orders: 2)
    RawWb::AnalyticsSearchTerm.create!(
      account: @wb_account, period_from:, period_to:,
      keyword:, nm_id: 71_001, frequency:, avg_position:,
      median_position: 30, open_card:, add_to_cart:, orders:, raw_json: {}, synced_at: Time.current
    )
  end

  def create_wb_summary(period_from: @period_from, period_to: @period_to,
    avg_position: 33, open_card: 62, add_to_cart: 8, orders: 1)
    RawWb::SearchReportProduct.create!(
      account: @wb_account, period_from:, period_to:, nm_id: 71_001,
      avg_position:, open_card:, add_to_cart:, open_to_cart: 13,
      orders:, cart_to_order: 13, visibility: 50, raw_json: {}, synced_at: Time.current
    )
  end
end
