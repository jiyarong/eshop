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
    @user.destroy!
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
    assert_select "h2", text: "计算过程"
    assert_select "#sku-sales-forecast-calculation-version_1", text: /加权销量合计/
    assert_select "#sku-sales-forecast-calculation-version_2", text: /连续需求/
    assert_select "input[name='from_date'], input[name='to_date']", count: 0
    assert_select "input[name='as_of_date'][min], input[name='as_of_date'][max]", count: 0
    assert_select "td", text: "2026-08-01"
    assert_select "#sku-sales-forecast-history tbody td", text: "2026-08-28"
    assert_select "#sku-sales-forecast-history tbody td", text: "2026-08-29", count: 0
  end

  test "adapts history to a cutoff outside stale history parameters" do
    get reports_sku_sales_forecast_path, params: {
      sku_code: @sku_code,
      from_date: @from_date,
      to_date: @from_date + 27.days,
      as_of_date: @from_date - 1.day
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='as_of_date'][value=?]", "2026-07-31"
    assert_select "#sku-sales-forecast-history-period", text: /2026-06-06.*2026-08-07/
    assert_select "#sku-sales-forecast-history tbody tr", count: 63
    assert_select "#sku-sales-forecast-history tbody td", text: "2026-08-01"
    assert_select "#sku-sales-forecast-calculation-version_1", text: /没有可用于计算的有效观察日/
  end

  test "defaults the cutoff to today in the user time zone" do
    @user.update!(time_zone: "UTC")
    travel_to Time.utc(2026, 10, 14, 20) do
      get reports_sku_sales_forecast_path, headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "input[name='as_of_date'][value=?]", "2026-10-14"
    end
  end

  test "shows followup history only through today in the user time zone" do
    @user.update!(time_zone: "UTC")
    travel_to Time.utc(2026, 8, 25, 20) do
      get reports_sku_sales_forecast_path, params: {
        sku_code: @sku_code, as_of_date: Date.new(2026, 8, 23)
      }, headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "#sku-sales-forecast-history-period", text: /2026-06-29.*2026-08-25/
      assert_select "#sku-sales-forecast-history tbody tr", count: 58
      assert_select "#sku-sales-forecast-history tbody td", text: "2026-08-25"
      assert_select "#sku-sales-forecast-history tbody td", text: "2026-08-26", count: 0
      assert_select "#sku-sales-forecast-calculation-version_2", text: /训练窗口：2026-07-27 ~ 2026-08-23/
    end
  end

  test "renders intermittent calculations in every supported locale" do
    Ec::Snapshot.where(sku_id: @sku.id).find_each do |snapshot|
      content = snapshot.content.deep_dup
      content["overview"]["daily_sales"] = snapshot.snapshot_date == @from_date + 20.days ? 4 : 0
      snapshot.update!(content: content)
    end

    I18n.available_locales.each do |locale|
      sign_in @user
      get reports_sku_sales_forecast_path, params: {
        sku_code: @sku_code, as_of_date: @from_date + 20.days, locale: locale
      }, headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "[id^='sku-sales-forecast-calculation-'] .translation_missing", count: 0
      assert_select "#sku-sales-forecast-calculation-version_2 p",
        text: I18n.t("reports.sku_sales_forecast.calculation.v2_intermittent", locale: locale, mean: "4", rate: "0.1286", result: "0.5143")
    end
  end
end
