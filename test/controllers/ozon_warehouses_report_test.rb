require "test_helper"

class OzonWarehousesReportTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(6)
    @user = create_user_with_roles("ozon-warehouses-#{@token}@example.com", "manager")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Ozon warehouse UI #{@token}", company_type: "general", ozon_raw_account_id: 920_000_000 + rand(10_000))
    @sku = Ec::Sku.create!(sku_code: "OWUI-#{@token.upcase}", product_name: "Ozon UI product")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "OWUI-P-#{@token}", platform_sku_id: "OWUI-S-#{@token}")
    @wb_account = RawWb::SellerAccount.create!(name: "WB unified #{@token}", api_token: "token-#{@token}", company_type: "small", is_active: true)
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "WB unified #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id)
    @wb_product = Ec::SkuProduct.create!(sku: @sku, store: @wb_store, product_id: (930_000_000 + rand(10_000)).to_s)
    Ec::SkuProductOperator.create!(sku_product: @product, user: @user)
    sign_in @user
  end

  teardown do
    Ec::SkuProductOperator.where(sku_product_id: @product&.id).delete_all
    Ec::SkuProduct.where(id: [@product&.id, @wb_product&.id].compact).delete_all
    Ec::Store.where(id: [@store&.id, @wb_store&.id].compact).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku&.sku_code).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    @user&.destroy
  end

  test "unified warehouse report switches platform by selected store" do
    get reports_warehouses_path, params: { store_id: @store.id, locale: "zh" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", text: "分仓"
    assert_select "form.warehouses-filter[action='#{reports_warehouses_path}']"
    assert_select "input[type='hidden'][name='store_id'][value='#{@store.id}']"
    assert_select ".warehouse-store-tags a[href*='store_id=#{@store.id}']", text: @store.store_name
    assert_select ".warehouse-store-tags a[href*='store_id=#{@wb_store.id}']", text: @wb_store.store_name
    assert_select ".weekly-profit-filter-block", count: 2
    filter_blocks = css_select("form.warehouses-filter > .weekly-profit-filter-block")
    assert filter_blocks.first.at_css(".supply-order-primary-filters")
    assert filter_blocks.last.at_css(".warehouse-store-tags")
    assert_select "#warehouse-spu-sku-filter-trigger", text: "全部 SPU / SKU"
    assert_select ".warehouse-store-tags a.is-active[aria-pressed='true']", text: @store.store_name
    assert_select ".summary-label", text: "FBO 可售库存"
    assert_select ".summary-label", text: "仓库匹配率", count: 0
    assert_select ".ozon-warehouse-tabs a[href^='#{reports_warehouses_path}']", minimum: 2

    sign_in @user
    get reports_warehouses_path, params: { store_id: @wb_store.id, locale: "zh" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", text: "分仓"
    assert_select "input[type='hidden'][name='store_id'][value='#{@wb_store.id}']"
    assert_select ".warehouse-store-tags a.is-active[aria-pressed='true']", text: @wb_store.store_name
    assert_select ".summary-label", text: "FBW 可用库存"
    assert_select ".summary-label", text: "仓库匹配率"
    assert_select ".ozon-warehouse-tabs a[href^='#{reports_warehouses_path}']", minimum: 2
  end

  test "renders the report for one selected Ozon store" do
    get reports_ozon_warehouses_path, params: { store_id: @store.id, locale: "zh" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", text: "Ozon 分仓"
    assert_select "select[name='store_id'] option[selected][value='#{@store.id}']", text: @store.store_name
    assert_select "table.ozon-warehouse-table[data-controller='hierarchy-table']"
    assert_select "th", text: "商品 / 集群 / 仓库"
    assert_select ".ozon-warehouse-fbs-stock", text: "FBS 可用 0"
    assert_select ".ozon-warehouse-formula-help[aria-label='查看建议新增发货量计算说明']", count: 2
    assert_select ".ozon-warehouse-status-help[aria-label='查看库存状态计算说明']", count: 1
    assert_select ".ozon-warehouse-product-row .ozon-warehouse-toggle[aria-expanded='false']"
    assert_select ".ozon-warehouse-tabs a", text: "根据商品"
    assert_select ".ozon-warehouse-tabs a[href*='view=clusters']", text: "按集群"
    assert_select "#ozon-warehouse-responsible-user-filter-operator-trigger", text: "全部运营人员"
    assert_select "input[name='operator_id'][type='hidden']"
    assert_select "input[name='developer_id']", count: 0

    sign_in @user
    get reports_ozon_warehouses_path, params: { store_id: @store.id, locale: "zh", view: "clusters", operator_id: @user.id }, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select ".ozon-warehouse-tabs a.is-active[aria-current='page']", text: "按集群"
    assert_select "#ozon-warehouse-responsible-user-filter-operator-trigger", text: @user.display_name
    assert_select "input[name='operator_id'][value='#{@user.id}']"
  end

  test "paginates products ten per page and preserves filters" do
    additional_skus = 10.times.map do |index|
      sku = Ec::Sku.create!(sku_code: "OWUI-#{@token.upcase}-#{index}", product_name: "Ozon UI product #{index}")
      Ec::SkuProduct.create!(sku: sku, store: @store, product_id: "OWUI-P-#{@token}-#{index}", platform_sku_id: "OWUI-S-#{@token}-#{index}")
      sku
    end

    get reports_ozon_warehouses_path, params: { store_id: @store.id, target_days: 35, locale: "zh" }, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "tr.ozon-warehouse-product-row", count: 10
    assert_select ".ozon-warehouse-pagination"
    assert_select "a[href*='page=2'][href*='store_id=#{@store.id}'][href*='target_days=35']"

    sign_in @user
    get reports_ozon_warehouses_path, params: { store_id: @store.id, target_days: 35, locale: "zh", page: 2 }, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "tr.ozon-warehouse-product-row", count: 1
  ensure
    if additional_skus
      Ec::SkuProduct.where(store_id: @store.id, sku_code: additional_skus.map(&:sku_code)).delete_all
      Ec::Sku.with_deleted.where(id: additional_skus.map(&:id)).delete_all
    end
  end
end
