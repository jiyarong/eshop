require "test_helper"

class OzonWarehousesReportTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(6)
    @user = create_user_with_roles("ozon-warehouses-#{@token}@example.com", "manager")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Ozon warehouse UI #{@token}", company_type: "general", ozon_raw_account_id: 920_000_000 + rand(10_000))
    @sku = Ec::Sku.create!(sku_code: "OWUI-#{@token.upcase}", product_name: "Ozon UI product")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "OWUI-P-#{@token}", platform_sku_id: "OWUI-S-#{@token}")
    sign_in @user
  end

  teardown do
    Ec::SkuProduct.where(id: @product&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku&.sku_code).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    @user&.destroy
  end

  test "renders the report for one selected Ozon store" do
    get reports_ozon_warehouses_path, params: { store_id: @store.id, locale: "zh" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", text: "Ozon 分仓"
    assert_select "select[name='store_id'] option[selected][value='#{@store.id}']", text: @store.store_name
    assert_select "table.ozon-warehouse-table[data-controller='hierarchy-table']"
    assert_select "th", text: "商品 / 集群 / 仓库"
  end
end
