require "test_helper"

class SkuSalesForecastControllerTest < ActionDispatch::IntegrationTest
  setup do
    @sku_code = "FORECAST-CONTROLLER-#{SecureRandom.hex(4).upcase}"
    @user = create_user_with_roles("forecast-#{@sku_code.downcase}@example.com", "super_admin")
    sign_in @user
    @sku = Ec::Sku.create!(sku_code: @sku_code, product_name: "Forecast controller", is_active: true)
    @from_date = Date.new(2026, 8, 1)
    Ec::Snapshot.insert_all!(28.times.map do |index|
      {
        snapshot_type: Ec::InventorySnapshot.snapshot_type,
        snapshot_date: @from_date + index.days,
        sku_id: @sku.id,
        content: {
          overview: {
            daily_sales: 4,
            daily_sales_velocity: 4,
            platform_stock: 20,
            book_stock: 30,
            out_of_stock: false
          }
        }
      }
    end)
  end

  teardown do
    Ec::Snapshot.where(sku_id: @sku.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "renders existing and both new forecast versions with historical tables" do
    get reports_sku_sales_forecast_path, params: {
      sku_code: @sku_code,
      from_date: @from_date,
      to_date: @from_date + 27.days,
      as_of_date: @from_date + 20.days
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU 销量预测"
    assert_select "form[action=?][method=?]", reports_sku_sales_forecast_path, "get"
    assert_select "a.erp-nav__link[href=?]", reports_sku_sales_forecast_path, text: "SKU 销量预测"
    assert_select ".spu-sku-filter[data-spu-sku-filter-all-label-value=?]", "选择 SKU"
    assert_select ".spu-sku-filter input[type='radio'][name='sku_code'][value=?][checked]", @sku_code
    assert_select ".sku-sales-forecast-summary .summary-label", text: "简单预测日销"
    assert_select ".sku-sales-forecast-summary .summary-label", text: "严谨预测日销"
    assert_select ".sku-sales-forecast-summary .weekly-profit-summary-card", count: 4
    assert_select "h2", text: "历史预测对比"
    assert_select "h2", text: "历史数据"
    assert_select "td", text: "2026-08-01"
  end
end
