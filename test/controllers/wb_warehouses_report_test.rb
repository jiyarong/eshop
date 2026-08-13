require "test_helper"

class WbWarehousesReportTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(6)
    @user = create_user_with_roles("wb-warehouses-#{@token}@example.com", "manager")
    @account = RawWb::SellerAccount.create!(name: "WB UI #{@token}", api_token: "token-#{@token}", company_type: "small", is_active: true)
    @store = Ec::Store.create!(platform: "wb", store_name: "WB UI #{@token}", company_type: "general", wb_raw_account_id: @account.id)
    @sku = Ec::Sku.create!(sku_code: "WBUI-#{@token.upcase}", product_name: "WB UI product")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: (500_000_000 + rand(10_000)).to_s)
    Ec::SkuProductOperator.create!(sku_product: @product, user: @user)
    sign_in @user
  end

  teardown do
    Ec::SkuProductOperator.where(sku_product_id: @product&.id).delete_all
    Ec::SkuProduct.where(id: @product&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku&.sku_code).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    @user&.destroy
  end

  test "renders product and cluster WB warehouse views" do
    get reports_wb_warehouses_path, params: { store_id: @store.id, locale: "zh" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", text: "WB 分仓"
    assert_select "select[name='store_id'] option[selected][value='#{@store.id}']", text: @store.store_name
    assert_select "table.ozon-warehouse-table[data-controller='hierarchy-table']"
    assert_select "th", text: "商品 / 集群 / 仓库"
    assert_select ".summary-label", text: "仓库匹配率"
    assert_select ".summary-label", text: "平台在途"
    assert_select "th", text: "平台在途"
    assert_select ".ozon-warehouse-fbs-stock", text: "FBS 可用 0"
    assert_select ".ozon-warehouse-tabs a", text: "根据商品"
    assert_select ".ozon-warehouse-tabs a[href*='view=clusters']", text: "按集群"
    assert_select "#wb-warehouse-responsible-user-filter-operator-trigger", text: "全部运营人员"
    assert_select "input[name='operator_id'][type='hidden']"
    assert_select "input[name='developer_id']", count: 0

    sign_in @user
    get reports_wb_warehouses_path, params: { store_id: @store.id, locale: "zh", view: "clusters", operator_id: @user.id }, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select ".ozon-warehouse-tabs a.is-active[aria-current='page']", text: "按集群"
    assert_select "#wb-warehouse-responsible-user-filter-operator-trigger", text: @user.display_name
    assert_select "input[name='operator_id'][value='#{@user.id}']"
  end

  test "paginates products with the standard pagination and preserves filters" do
    additional_skus = 10.times.map do |index|
      sku = Ec::Sku.create!(sku_code: "WBUI-#{@token.upcase}-#{index}", product_name: "WB UI product #{index}")
      Ec::SkuProduct.create!(sku: sku, store: @store, product_id: (600_000_000 + index + rand(10_000)).to_s)
      sku
    end

    get reports_wb_warehouses_path,
      params: { store_id: @store.id, target_days: 35, locale: "zh" },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "tr.ozon-warehouse-product-row", count: 10
    assert_select ".inventory-pagination-bar.ozon-warehouse-pagination"
    assert_select ".pagination-chip", text: "第 1/2 页"
    assert_select ".pagination-nav .pg-btn", text: "2"
    assert_select "a[href*='page=2'][href*='store_id=#{@store.id}'][href*='target_days=35']"
    assert_select "form.pagination-jump[action='#{reports_wb_warehouses_path}']"
    assert_select "form.pagination-jump input[name='store_id'][value='#{@store.id}']"
    assert_select "form.pagination-jump input[name='target_days'][value='35']"

    sign_in @user
    get reports_wb_warehouses_path,
      params: { store_id: @store.id, target_days: 35, locale: "zh", jump_page: 2, current_page: 1 },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "tr.ozon-warehouse-product-row", count: 1
    assert_select ".pagination-chip", text: "第 2/2 页"
    assert_select ".pagination-nav .pg-btn.on", text: "2"
  ensure
    if additional_skus
      Ec::SkuProduct.where(store_id: @store.id, sku_code: additional_skus.map(&:sku_code)).delete_all
      Ec::Sku.with_deleted.where(id: additional_skus.map(&:id)).delete_all
    end
  end
end
