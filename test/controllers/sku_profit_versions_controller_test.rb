require "test_helper"

class SkuProfitVersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    token = SecureRandom.hex(5)
    @user = create_user_with_roles("profit-versions-#{token}@example.com", "manager")
    sign_in @user
    @sku = Ec::Sku.create!(sku_code: "PV-#{token.upcase}", product_name: "Profit version test", is_active: true)
    Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      effective_on: Date.new(2026, 1, 1),
      purchase_price_cny: 10,
      freight_to_by_cny: 2,
      customs_misc_cny: 1,
      customs_duty_rate: 0.1,
      import_vat_rate: 0.2,
      pkg_length_cm: 10,
      pkg_width_cm: 20,
      pkg_height_cm: 30
    )
  end

  teardown do
    version_ids = Ec::SkuProfitVersion.where(sku_id: @sku&.id).pluck(:id)
    context_ids = Ec::SkuProfitVersionContext.where(sku_profit_version_id: version_ids).pluck(:id)
    cost_ids = Ec::SkuCost.where(sku_code: @sku&.sku_code).pluck(:id)
    dimension_ids = Ec::SkuDimension.where(sku_code: @sku&.sku_code).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersionContext", record_id: context_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: version_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuCost", record_id: cost_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuDimension", record_id: dimension_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku&.id).delete_all
    Ec::SkuProfitVersionContext.where(id: context_ids).delete_all
    Ec::SkuProfitVersion.where(id: version_ids).delete_all
    Ec::SkuCost.where(id: cost_ids).delete_all
    Ec::SkuDimension.where(id: dimension_ids).delete_all
    Ec::Sku.where(id: @sku&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "creates one draft with multiple contexts" do
    post report_sku_profit_versions_path(@sku.sku_code), params: {
      version: { name: "Initial model", status: "draft", effective_from: "2026-09-01" },
      contexts: [
        { platform: "WB", market: "RU", delivery_mode: "FBO", warehouse_region: "MAIN", company_type: "GENERAL", inputs: { price_rub: "100", profit_cny: "999" } },
        { platform: "WB", market: "RU", delivery_mode: "FBS", warehouse_region: "MAIN", company_type: "GENERAL" }
      ]
    }, as: :json

    assert_response :created
    payload = response.parsed_body
    assert_equal "draft", payload.fetch("status")
    assert_equal 2, payload.fetch("contexts").size
    assert_equal %w[fbo fbs], payload.fetch("contexts").map { |context| context.fetch("delivery_mode") }.sort
    context = payload.fetch("contexts").find { |candidate| candidate.fetch("delivery_mode") == "fbo" }
    assert_equal 100.to_d, context.fetch("price_rub").to_d
    assert_equal 10.to_d, context.fetch("purchase_price_cny").to_d
    assert_equal 13.to_d, context.fetch("exchange_rate_rub_cny").to_d
    assert_equal 0.1.to_d, context.fetch("return_rate").to_d
    assert_equal 1.55.to_d, context.fetch("logistics_coeff").to_d
    assert_equal 0.015.to_d, context.fetch("acquiring_rate").to_d
    assert_equal 60.to_d, context.fetch("wb_logistics_base_rub").to_d
    assert_equal 50.to_d, context.fetch("wb_fixed_return_base_rub").to_d
    assert_equal 2.to_d, context.fetch("misc_cny").to_d
    assert_equal "incomplete", context.fetch("calculation_status")
    assert_nil context.fetch("profit_cny")
    assert_equal 1, @sku.profit_versions.where(name: "Initial model").count
  end

  test "creates the six standard contexts when no contexts are submitted" do
    post report_sku_profit_versions_path(@sku.sku_code), params: {
      version: { name: "Default scenarios", status: "draft", effective_from: "2026-09-01" }
    }, as: :json

    assert_response :created
    payload = response.parsed_body
    scenarios = payload.fetch("contexts").map do |context|
      context.slice("platform", "market", "delivery_mode", "warehouse_region", "company_type")
    end
    assert_equal Ec::SkuProfitStandardContexts::SCENARIOS, scenarios
    assert payload.fetch("contexts").all? { |context| context.fetch("calculation_status") == "incomplete" }
    assert payload.fetch("contexts").all? { |context| context.fetch("return_rate").to_d == 0.1.to_d }
  end

  test "publishing validates every context and rolls back the whole version" do
    assert_no_difference -> { @sku.profit_versions.count } do
      post report_sku_profit_versions_path(@sku.sku_code), params: {
        version: { name: "Invalid published model", status: "published", effective_from: Date.current.to_s },
        contexts: [
          {
            platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
            inputs: valid_wb_profit_inputs
          },
          {
            platform: "ozon", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
            inputs: { price_rub: 10_800 }
          }
        ]
      }, as: :json
    end

    assert_response :unprocessable_entity
    assert response.parsed_body.fetch("errors").key?("calculation_status")
  end

  test "published version is returned with its child contexts" do
    post report_sku_profit_versions_path(@sku.sku_code), params: {
      version: { name: "Published model", status: "published", effective_from: Date.current.to_s },
      contexts: [{
        platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
        inputs: valid_wb_profit_inputs
      }]
    }, as: :json
    assert_response :created
    version_id = response.parsed_body.fetch("id")

    sign_in @user
    get report_sku_profit_versions_path(@sku.sku_code), as: :json

    assert_response :success
    payload = response.parsed_body.find { |version| version.fetch("id") == version_id }
    assert_equal "published", payload.fetch("status")
    context = payload.fetch("contexts").sole
    assert_equal "wb", context.fetch("platform")
    assert_equal "valid", context.fetch("calculation_status")
    assert_equal "excel_baseline_v4", context.fetch("formula_version")
    assert context.fetch("profit_cny").present?
  end

  test "updates all changed contexts atomically and increments lock" do
    version = @sku.profit_versions.create!(name: "Draft", status: "draft", effective_from: Date.current)
    fbo = version.contexts.create!(platform: "wb", market: "ru", delivery_mode: "fbo", price_rub: 1_000)
    fbs = version.contexts.create!(platform: "wb", market: "ru", delivery_mode: "fbs")

    patch report_sku_profit_version_path(@sku.sku_code, version), params: {
      version: { name: "Updated draft", lock_version: version.lock_version },
      contexts: [
        { id: fbo.id, platform: "wb", market: "ru", delivery_mode: "fbo", inputs: { commission_rate: "0.10" } },
        { id: fbs.id, platform: "wb", market: "ru", delivery_mode: "fbs", inputs: { commission_rate: "0.20" } }
      ]
    }, as: :json

    assert_response :success
    version.reload
    assert_equal "Updated draft", version.name
    assert_equal 1, version.lock_version
    assert_equal 1_000.to_d, fbo.reload.price_rub
    assert_equal 0.10.to_d, fbo.reload.commission_rate
    assert_equal 0.20.to_d, fbs.reload.commission_rate
  end

  test "saving a draft recalculates and persists its formula columns" do
    post report_sku_profit_versions_path(@sku.sku_code), params: {
      version: { name: "Calculated draft", status: "draft", effective_from: Date.current.to_s },
      contexts: [{
        platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
        inputs: valid_wb_profit_inputs
      }]
    }, as: :json

    assert_response :created
    payload = response.parsed_body.fetch("contexts").sole
    assert_equal "valid", payload.fetch("calculation_status")
    assert payload.fetch("profit_cny").present?

    context = Ec::SkuProfitVersionContext.find(payload.fetch("id"))
    assert_equal "valid", context.calculation_status
    assert_equal payload.fetch("profit_cny").to_d, context.profit_cny
    assert context.calculated_at.present?
  end

  test "returns conflict for a stale lock" do
    version = @sku.profit_versions.create!(name: "Draft", status: "draft", effective_from: Date.current)
    stale_lock = version.lock_version
    version.update!(note: "newer write")

    patch report_sku_profit_version_path(@sku.sku_code, version), params: {
      version: { note: "stale write", lock_version: stale_lock }
    }, as: :json

    assert_response :conflict
    assert_equal ["stale"], response.parsed_body.dig("errors", "base")
    assert_equal "newer write", version.reload.note
  end

  test "renders the profit prediction tab as a six-row calculation workbench" do
    get report_sku_path(@sku.sku_code),
      params: { tab: "profit_prediction", locale: "en" },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".profit-prediction-toolbar" do
      assert_select ".section-title", text: "Profit forecast"
      assert_select ".profit-prediction-version-switcher select[data-profit-prediction-target='navigationControl']"
      assert_select ".profit-prediction-toolbar__statuses .profit-prediction-status", count: 0
      assert_select ".profit-prediction-version-switcher > span", count: 0
      assert_select ".profit-prediction-toolbar__actions"
    end
    assert_select "button[data-profit-prediction-target='publishButton']", count: 0
    assert_select ".profit-prediction-workbench.is-calculating"
    assert_select ".profit-prediction-workbench[data-profit-prediction-actual-logistics-url-value]"
    assert_select ".profit-prediction-workbench[data-profit-prediction-official-commission-url-value]"
    assert_select ".profit-prediction-header", count: 0
    assert_select ".profit-prediction-version-bar", count: 0
    assert_select ".table-viewport[data-sticky-table-header-sticky-columns-value='5']"
    assert_select ".profit-prediction-table"
    assert_select ".profit-prediction-platform-tabs [data-profit-prediction-target='platformFilter']", count: 3
    assert_select ".profit-prediction-platform-tab.is-active[data-platform-value='']", count: 1
    assert_select "[data-platforms='wb'][data-platform-column-group]", minimum: 1
    assert_select "[data-platforms='ozon'][data-platform-column-group]", minimum: 1
    assert_select "th", text: "Amortized return logistics CNY", count: 1
    assert_select "th", text: "Target sale price (RUB)", count: 1
    assert_select "tr[data-profit-prediction-target='row']", count: 6
    assert_select "tr[data-profit-prediction-target='row'][tabindex='0'][aria-selected='false']", count: 6
    assert_select "tr[data-action*='profit-prediction#selectRow']", count: 6
    assert_select ".profit-prediction-table__identity-heading", count: 4
    assert_select ".profit-prediction-table__identity-heading--warehouse_region", count: 0
    assert_select "td.profit-prediction-table__identity--warehouse_region", count: 0
    assert_select "td[data-row-status][data-status='pending']", count: 6
    assert_select "input[type='number'][data-field='logistics_coeff']", count: 4
    assert_select "input[type='number'][data-field='outbound_logistics_rub']", count: 2
    assert_select "input[type='number'][data-field='price_rub']:not([disabled])", count: 6
    assert_select "input[type='number'][data-field='length_cm'][disabled]", count: 6
    document = Nokogiri::HTML(response.body)
    rows = document.css("tr[data-profit-prediction-target='row']")
    scenario_tabs = document.css(".profit-prediction-process__scenario-tab[data-profit-prediction-target='scenarioTab']")
    assert_equal 6, scenario_tabs.size
    assert_equal 1, scenario_tabs.count { |tab| tab["aria-selected"] == "true" && tab["tabindex"] == "0" }
    assert_equal rows.map { |row| row["data-row-key"] }, scenario_tabs.map { |tab| tab["data-row-key"] }
    assert scenario_tabs.all? { |tab| tab["data-action"].include?("profit-prediction#selectScenarioTab") }
    actual_scenarios = rows.map do |row|
      {
        "platform" => row["data-platform"],
        "market" => row["data-market"],
        "delivery_mode" => row["data-delivery-mode"],
        "warehouse_region" => row["data-warehouse-region"],
        "company_type" => row["data-company-type"]
      }
    end
    assert_equal Ec::SkuProfitStandardContexts::SCENARIOS, actual_scenarios
    assert rows.all? { |row| row.at_css("input[data-field='exchange_rate_rub_cny']")["value"] == "13.00" }
    assert rows.all? { |row| row.at_css("input[data-field='exchange_rate_rub_cny']")["data-source-value"] == "13.0" }
    wb_rows = rows.select { |row| row["data-platform"] == "wb" }
    assert wb_rows.all? { |row| row.at_css("input[data-field='return_rate']")["value"].to_d == 0.1.to_d }
    small_fbo = rows.find do |row|
      row["data-platform"] == "wb" && row["data-company-type"] == "small" && row["data-delivery-mode"] == "fbo"
    end
    assert_equal 1.3.to_d, small_fbo.at_css("input[data-field='logistics_coeff']")["value"].to_d
    ozon_rows = rows.select { |row| row["data-platform"] == "ozon" }
    assert ozon_rows.all? { |row| row.at_css("input[data-field='warehouse_operation_rub']")["value"].to_d == 25.to_d }
    assert ozon_rows.all? { |row| row.at_css("input[data-field='return_rate']")["value"].to_d == 0.1.to_d }
    assert_select "tr[data-platform='ozon'][data-market='ru'][data-company-type='general']" do
      assert_select "input[type='number'][data-field='import_vat_rate'][disabled][value='0.2']"
      assert_select "input[type='number'][data-field='length_cm'][disabled][value='10.00']"
      assert_select "input[type='number'][data-field='width_cm'][disabled][value='20.00']"
      assert_select "input[type='number'][data-field='height_cm'][disabled][value='30.00']"
    end
    assert_select "tr[data-platform='ozon'][data-market='by'][data-company-type='general']" do
      assert_select "input[type='number'][data-field='import_vat_rate']:not([disabled])"
      assert_select "input[type='number'][data-field='length_cm'][disabled]"
    end
    group_labels = document.css(".profit-prediction-table__groups th").map { |header| header.text.strip }
    assert_equal ["Scenario", "Product cost and dimensions", "Logistics and other costs", "Price and rates", "Formula results"], group_labels
    assert_includes response.body, "Belarus revenue = __BY_PRICE__ / __EXCHANGE__; Russia fee base = __RF_PRICE__ / __EXCHANGE__"
    ordered_fields = document.at_css("tr[data-profit-prediction-target='row']").css("[data-field]").map { |input| input["data-field"] }
    assert_operator ordered_fields.index("price_rub"), :<, ordered_fields.index("other_cny")
    assert_select "button[data-action='profit-prediction#save']", text: /Save calculation/
      assert_select ".profit-prediction-process" do
        assert_select "h3", text: "Calculation for selected scenario"
        assert_select ".profit-prediction-process__summary"
        assert_select "[data-profit-prediction-target='detailPrice']"
        assert_select "[data-profit-prediction-target='detailTotalCost']"
        assert_select "[data-profit-prediction-target='detailProfit']"
        assert_select "[data-profit-prediction-target='detailMargin']"
        assert_select "[data-profit-prediction-target='detailCostFormula']", count: 1
        assert_select "[data-profit-prediction-target='detailProfitFormula']", count: 1
        assert_select "[data-profit-prediction-target='detailMarginFormula']", count: 1
        assert_select ".profit-prediction-process__status[hidden]", count: 1
        assert_select "th", text: "Item"
        assert_select "th", text: "Parameters"
        assert_select "th", text: "Source & shortcuts"
        assert_select "th", text: "Calculation and result"
      assert_select "tbody[data-profit-prediction-target='detailBody']"
    end
    assert_select "dialog[data-profit-prediction-target='tariffDialog']", count: 1
    assert_select "#profit-prediction-ozon-origins-trigger", count: 1
    assert_select "#profit-prediction-ozon-destinations-trigger", count: 1
    assert_no_match(/translation missing/i, response.body)
    assert_match(/View official commission rate/, response.body)
  end

  test "renders only applicable inputs for each scenario row" do
    get report_sku_path(@sku.sku_code),
      params: { tab: "profit_prediction" },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td.profit-prediction-table__identity--company_type", text: "一般", count: 4
    assert_select "td.profit-prediction-table__identity--company_type", text: "小规模", count: 2
    assert_select "tr[data-platform='wb'][data-company-type='small'][data-delivery-mode='fbo']" do
      assert_select "input[data-field='wb_logistics_base_rub']"
      assert_select "input[data-field='logistics_tax_rate']"
      assert_select "input[data-field='tax_rate']"
      assert_select "input[type='number'][data-field='wb_fixed_return_base_rub']", count: 0
      assert_select "input[type='number'][data-field='sales_vat_rate']", count: 0
    end
    assert_select "tr[data-platform='ozon'][data-market='by']" do
      assert_select "input[data-field='price_rub']"
      assert_select "input[data-field='rf_price_rub']", count: 0
      assert_select "input[data-field='outbound_logistics_rub']"
      assert_select "input[data-field='return_logistics_rub']"
      assert_select "input[data-field='warehouse_operation_rub']"
      assert_select "input[data-field='sales_vat_rate']"
      assert_select ".profit-prediction-table__not-applicable", text: /白俄场景不适用，不参与计算/, count: 1
      assert_select "input[data-field='length_cm'][disabled]"
      assert_select "input[data-field='width_cm'][disabled]"
      assert_select "input[data-field='height_cm'][disabled]"
      assert_select "input[type='number'][data-field='logistics_coeff']", count: 0
    end

    expected_fields = {
      ["wb", "general"] => %w[
        purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
        length_cm width_cm height_cm price_rub exchange_rate_rub_cny commission_rate
        acquiring_rate advertising_rate sales_vat_rate logistics_coeff return_rate
        wb_logistics_base_rub wb_logistics_liter_rub wb_fixed_return_base_rub fbo_delivery_cny storage_cny
        damage_rate misc_cny other_cny
      ],
      ["wb", "small"] => %w[
        purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
        length_cm width_cm height_cm price_rub exchange_rate_rub_cny commission_rate
        acquiring_rate advertising_rate tax_rate logistics_coeff return_rate
        logistics_tax_rate wb_logistics_base_rub wb_logistics_liter_rub fbo_delivery_cny storage_cny
        damage_rate misc_cny other_cny
      ],
      ["ozon", "ru"] => %w[
        purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
        length_cm width_cm height_cm price_rub exchange_rate_rub_cny commission_rate
        acquiring_rate advertising_rate other_cny storage_cny return_rate outbound_logistics_rub
        return_logistics_rub warehouse_operation_rub cross_docking_cny
      ],
      ["ozon", "by"] => %w[
        purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
        length_cm width_cm height_cm price_rub exchange_rate_rub_cny
        commission_rate acquiring_rate advertising_rate sales_vat_rate other_cny storage_cny return_rate
        outbound_logistics_rub return_logistics_rub warehouse_operation_rub
      ]
    }
    document = Nokogiri::HTML(response.body)
    document.css("tr[data-profit-prediction-target='row']").each do |row|
      key = row["data-platform"] == "wb" ? ["wb", row["data-company-type"]] : ["ozon", row["data-market"]]
      actual_fields = row.css("input[type='number'][data-profit-prediction-target~='input']").map { |input| input["data-field"] }
      assert_equal expected_fields.fetch(key).sort, actual_fields.sort, "unexpected input matrix for #{key.join('/')}"
    end
  end

  test "renders a saved draft with inputs ready for direct calculation" do
    version = @sku.profit_versions.create!(name: "Saved draft", status: "draft", effective_from: Date.current)
    version.contexts.create!(
      platform: "wb", market: "ru", delivery_mode: "fbo", company_type: "general",
      purchase_price_cny: 10, length_cm: 10, width_cm: 20, height_cm: 30,
      price_rub: 1_000, exchange_rate_rub_cny: 10.123456, logistics_coeff: 1,
      return_rate: 0.1, commission_rate: 0.075,
      profit_cny: 12.3456, margin: 0.123456, calculation_status: "valid"
    )

    get report_sku_path(@sku.sku_code),
      params: { tab: "profit_prediction", version_id: version.id },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".profit-prediction-toolbar"
    assert_select ".profit-prediction-version-summary", count: 0
    assert_select ".profit-prediction-toolbar__editor", count: 0
    assert_select "input[type='hidden'][data-profit-prediction-target='versionInput']", count: 3
    assert_select "button[data-action='profit-prediction#enterCalculation']", count: 0
    assert_select "button[data-action='profit-prediction#cancelCalculation']", count: 0
    assert_select "input[data-field='price_rub']:not([disabled])[value='1000.00']"
    assert_select "input[data-field='exchange_rate_rub_cny'][value='10.12'][data-source-value='10.123456']"
    assert_select "input[data-field='commission_rate'][value='0.075'][data-source-value='0.075']"
    assert_select "td[data-row-status][data-status='valid']", count: 1
    assert_select "td[data-result-field='profit_cny']", text: "12.35"
    assert_select "td[data-result-field='margin']", text: "12.35%"
    assert_select "button[data-action='profit-prediction#save']:not([hidden])"
    assert_includes response.body, "目标成交价（RUB）"
    assert_includes response.body, "目标利润率"
    assert_no_match(/translation missing/i, response.body)
    assert_includes response.body, "参数不完整：__FIELDS__"
  end

  test "preview calculates only from the submitted row inputs" do
    @sku.costs.update_all(purchase_price_cny: 999)

    post preview_report_sku_profit_path(@sku.sku_code), params: {
      platform: "wb",
      parameter_context: { market: "ru", delivery_mode: "fbo", company_type: "general" },
      inputs: {
        purchase_price_cny: 270, freight_cny: 22.5, customs_misc_cny: 2.81,
        length_cm: 85, width_cm: 52, height_cm: 5,
        price_rub: 15_000, exchange_rate_rub_cny: 13,
        logistics_coeff: 1.55, return_rate: 0.18,
        commission_rate: 0.218, acquiring_rate: 0.031,
        sales_vat_rate: 0.2, misc_cny: 2
      }
    }, as: :json

    assert_response :success
    assert_in_delta 1_153.8461538462, response.parsed_body.fetch("revenue_cny").to_d, 0.000001
    assert_in_delta 295.5680487805, response.parsed_body.fetch("profit_cny").to_d, 0.000001
  end

  test "returns the current sku actual logistics source payload" do
    get report_sku_actual_logistics_path(@sku.sku_code), as: :json

    assert_response :success
    payload = response.parsed_body
    assert_equal "ozon", payload.fetch("platform")
    assert_equal 0, payload.fetch("store_count")
    assert_equal 0, payload.dig("outbound", "sample_count")
    assert_nil payload.dig("outbound", "average_rub")
    assert_nil payload.dig("return", "average_rub")
    assert_equal 0, payload.dig("cross_dock", "sample_count")
    assert_nil payload.dig("cross_dock", "average_rub")
    assert_equal 0, payload.dig("return_rate", "order_count")
    assert_equal 0, payload.dig("return_rate", "return_count")
    assert_nil payload.dig("return_rate", "rate")
  end

  test "returns actual return rates for both profit platforms" do
    %w[ozon wb].each do |platform|
      sign_in @user
      get report_sku_actual_return_rate_path(@sku.sku_code), params: { platform: platform }, as: :json

      assert_response :success
      payload = response.parsed_body
      assert_equal platform, payload.fetch("platform")
      assert_equal 0, payload.dig("return_rate", "order_count")
      assert_equal 0, payload.dig("return_rate", "return_count")
      assert_nil payload.dig("return_rate", "rate")
    end
  end

  test "rejects unsupported actual return rate platforms" do
    get report_sku_actual_return_rate_path(@sku.sku_code), params: { platform: "other" }, as: :json

    assert_response :unprocessable_entity
    assert_equal ["unsupported_platform"], response.parsed_body.fetch("errors")
  end

  test "returns the current sku actual storage payload for both platforms" do
    %w[ozon wb].each do |platform|
      sign_in @user
      get report_sku_actual_storage_path(@sku.sku_code), params: { platform: platform }, as: :json

      assert_response :success
      payload = response.parsed_body
      assert_equal platform, payload.fetch("platform")
      assert_equal 0, payload.dig("storage", "sample_count")
      assert_equal 0, payload.dig("storage", "sale_count")
      assert_nil payload.dig("storage", "average_rub")
    end
  end

  test "rejects unsupported actual storage platforms" do
    get report_sku_actual_storage_path(@sku.sku_code), params: { platform: "other" }, as: :json

    assert_response :unprocessable_entity
    assert_equal ["unsupported_platform"], response.parsed_body.fetch("errors")
  end

  test "returns the current sku actual selling price source payload" do
    get report_sku_actual_selling_price_path(@sku.sku_code), params: { platform: "ozon", market: "ru" }, as: :json

    assert_response :success
    payload = response.parsed_body
    assert_equal "ozon", payload.fetch("platform")
    assert_equal "ru", payload.fetch("market")
    assert_equal "RUB", payload.dig("price", "source_currency")
    assert_equal 0, payload.dig("price", "item_count")
    assert_nil payload.dig("price", "average_rub")
  end

  test "rejects unsupported actual selling price contexts" do
    get report_sku_actual_selling_price_path(@sku.sku_code), params: { platform: "amazon", market: "ru" }, as: :json

    assert_response :unprocessable_entity
    assert_equal ["unsupported_context"], response.parsed_body.fetch("errors")
  end

  test "returns the current sku actual advertising payload for the requested platform" do
    get report_sku_actual_advertising_path(@sku.sku_code), params: { platform: "wb" }, as: :json

    assert_response :success
    payload = response.parsed_body
    assert_equal "wb", payload.fetch("platform")
    assert_equal "RUB", payload.dig("advertising", "currency")
    assert_equal 0, payload.dig("coverage", "covered_account_weeks")
    assert_nil payload.fetch("rate")
  end

  test "rejects unsupported actual advertising platforms" do
    get report_sku_actual_advertising_path(@sku.sku_code), params: { platform: "amazon" }, as: :json

    assert_response :unprocessable_entity
    assert_equal ["unsupported_platform"], response.parsed_body.fetch("errors")
  end

  test "returns the official commission source payload for a supported scenario" do
    get report_sku_official_commission_rate_path(@sku.sku_code),
      params: { platform: "ozon", delivery_mode: "fbo" }, as: :json

    assert_response :success
    payload = response.parsed_body
    assert_equal "ozon", payload.fetch("platform")
    assert_equal "fbo", payload.fetch("delivery_mode")
    assert_equal "sales_percent_fbo", payload.dig("source", "field")
    assert_equal [], payload.fetch("rates")
  end

  test "rejects unsupported official commission contexts" do
    get report_sku_official_commission_rate_path(@sku.sku_code),
      params: { platform: "ozon", delivery_mode: "dbs" }, as: :json

    assert_response :unprocessable_entity
    assert_equal ["unsupported_context"], response.parsed_body.fetch("errors")
  end

  test "published versions remain editable through the update endpoint" do
    version = @sku.profit_versions.new(name: "Published", status: "published", effective_from: Date.current)
    version.contexts.build(
      platform: "wb", market: "ru", delivery_mode: "fbo", company_type: "general",
      purchase_price_cny: 10, length_cm: 10, width_cm: 20, height_cm: 30,
      price_rub: 1_000, exchange_rate_rub_cny: 10, logistics_coeff: 1,
      return_rate: 0.1, commission_rate: 0.1
    )
    version.save!

    patch report_sku_profit_version_path(@sku.sku_code, version), params: {
      version: { name: "Changed", lock_version: version.lock_version }
    }, as: :json

    assert_response :success
    assert_equal "Changed", version.reload.name
    assert_equal "published", version.status
  end

  private

  def valid_wb_profit_inputs
    {
      price_rub: 1_000,
      exchange_rate_rub_cny: 10,
      logistics_coeff: 1.2,
      return_rate: 0.2,
      commission_rate: 0.12
    }
  end
end
