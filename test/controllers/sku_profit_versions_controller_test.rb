require "test_helper"

class SkuProfitVersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    token = SecureRandom.hex(5)
    @user = create_user_with_roles("profit-versions-#{token}@example.com", "manager")
    sign_in @user
    @sku = Ec::Sku.create!(sku_code: "PV-#{token.upcase}", product_name: "Profit version test", is_active: true)
    # Workbench endpoints are limited to SKUs the signed-in user is assigned to.
    Ec::SkuOperatorAssignment.create!(sku: @sku, user: @user)
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
    visibility_ids = Ec::SkuScenarioVisibility.where(sku_id: @sku&.id).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuScenarioVisibility", record_id: visibility_ids).delete_all
    Ec::SkuScenarioVisibility.where(id: visibility_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku&.id).delete_all
    Ec::SkuOperatorAssignment.where(sku_code: @sku&.sku_code).delete_all
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
        { platform: "WB", market: "RU", delivery_mode: "FBO", warehouse_region: "MAIN", company_type: "GENERAL", inputs: { commission_base_price_rub: "100", profit_cny: "999" } },
        { platform: "WB", market: "RU", delivery_mode: "FBS", warehouse_region: "MAIN", company_type: "GENERAL" }
      ]
    }, as: :json

    assert_response :created
    payload = response.parsed_body
    assert_equal "draft", payload.fetch("status")
    assert_equal 2, payload.fetch("contexts").size
    assert_equal %w[fbo fbs], payload.fetch("contexts").map { |context| context.fetch("delivery_mode") }.sort
    context = payload.fetch("contexts").find { |candidate| candidate.fetch("delivery_mode") == "fbo" }
    assert_equal 100.to_d, context.fetch("commission_base_price_rub").to_d
    assert_equal 10.to_d, context.fetch("purchase_price_cny").to_d
    assert_equal 13.to_d, context.fetch("exchange_rate_rub_cny").to_d
    assert_equal 0.1.to_d, context.fetch("return_rate").to_d
    assert_equal 1.55.to_d, context.fetch("logistics_coeff").to_d
    assert_equal 0.015.to_d, context.fetch("acquiring_rate").to_d
    assert_equal 46.to_d, context.fetch("wb_logistics_base_rub").to_d
    assert_equal 50.to_d, context.fetch("wb_fixed_return_base_rub").to_d
    assert_equal 2.to_d, context.fetch("misc_cny").to_d
    assert_equal "incomplete", context.fetch("calculation_status")
    assert_nil context.fetch("profit_cny")
    assert_equal 1, @sku.profit_versions.where(name: "Initial model").count
  end

  test "creates every standard context when no contexts are submitted" do
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

  test "persists Ozon seller and buyer prices independently in both markets" do
    post report_sku_profit_versions_path(@sku.sku_code), params: {
      version: { name: "Separate Belarus prices", status: "draft", effective_from: "2026-09-01" },
      contexts: [
        {
          platform: "ozon", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
          inputs: { buyer_paid_price_rub: "15216.29", commission_base_price_rub: "27000" }
        },
        {
          platform: "ozon", market: "by", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
          inputs: { buyer_paid_price_rub: "15609", commission_base_price_rub: "25000" }
        }
      ]
    }, as: :json

    assert_response :created
    contexts = response.parsed_body.fetch("contexts")
    russia = contexts.find { |context| context.fetch("market") == "ru" }
    belarus = contexts.find { |context| context.fetch("market") == "by" }
    assert_equal 15_216.29.to_d, russia.fetch("buyer_paid_price_rub").to_d
    assert_equal 27_000.to_d, russia.fetch("commission_base_price_rub").to_d
    assert_equal 15_609.to_d, belarus.fetch("buyer_paid_price_rub").to_d
    assert_equal 25_000.to_d, belarus.fetch("commission_base_price_rub").to_d
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
            inputs: { commission_base_price_rub: 10_800 }
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
    fbo = version.contexts.create!(platform: "wb", market: "ru", delivery_mode: "fbo", commission_base_price_rub: 1_000)
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
    assert_equal 1_000.to_d, fbo.reload.commission_base_price_rub
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
    # Switching version reloads the tab's own frame from the SKU detail URL, never the host page.
    assert_select ".profit-prediction-workbench[data-profit-prediction-switch-url-value='#{report_sku_path(@sku.sku_code, tab: "profit_prediction")}']"
    # New and Copy ask for a name in a dialog first; they are buttons now, not links that build an unsaved version.
    assert_select ".profit-prediction-toolbar__version-actions button[data-action='profit-prediction#openVersionDialog']", count: 1
    assert_select ".profit-prediction-toolbar__version-actions button[data-version-action='new'][data-default-name]"
    assert_select ".profit-prediction-toolbar__version-actions a[href*='new_profit_version']", count: 0
    assert_select "dialog[data-profit-prediction-target='versionDialog'] input[data-profit-prediction-target='versionDialogName']", count: 1
    assert_select ".profit-prediction-workbench[data-profit-prediction-create-url-value='#{report_sku_profit_versions_path(@sku.sku_code)}']"
    assert_select ".profit-prediction-header", count: 0
    assert_select ".profit-prediction-version-bar", count: 0
    assert_select ".table-viewport[data-sticky-table-header-sticky-columns-value='5']"
    assert_select ".profit-prediction-table"
    assert_select ".profit-prediction-platform-tabs [data-profit-prediction-target='platformFilter']", count: 3
    assert_select ".profit-prediction-platform-tab.is-active[data-platform-value='']", count: 1
    assert_select "[data-platforms='wb'][data-platform-column-group]", minimum: 1
    assert_select "[data-platforms='ozon'][data-platform-column-group]", minimum: 1
    assert_select "th", text: "Amortized return logistics CNY", count: 1
    assert_select "th", text: "Commission base price (RUB)", count: 1
    assert_select "th", text: "Commission rate (%)", count: 1
    assert_select "th", text: "Logistics return rate (%)", count: 1
    assert_select "th", text: "Exchange rate (%)", count: 0
    assert_select "th", text: "Buyer-paid price incl. VAT (RUB)", count: 1
    assert_select "th", text: "VAT rate in the buyer price (%)", count: 1
    total = Ec::SkuProfitStandardContexts::SCENARIOS.size
    assert_select "tr[data-profit-prediction-target='row']", count: total
    assert_select "tr[data-profit-prediction-target='row'][tabindex='0'][aria-selected='false']", count: total
    assert_select "tr[data-action*='profit-prediction#selectRow']", count: total
    assert_select ".profit-prediction-table__identity-heading", count: 4
    assert_select ".profit-prediction-table__identity-heading--warehouse_region", count: 0
    assert_select "td.profit-prediction-table__identity--warehouse_region", count: 0
    assert_select "td[data-row-status][data-status='pending']", count: total
    assert_select "input[type='number'][data-field='logistics_coeff']", count: 8
    assert_select "input[type='number'][data-field='outbound_logistics_rub']", count: total
    assert_select "input[type='number'][data-field='commission_base_price_rub']:not([disabled])", count: total
    assert_select "input[type='number'][data-field='buyer_paid_price_rub']:not([disabled])", count: total
    assert_select "input[type='number'][data-field='buyer_price_vat_rate']:not([disabled])", count: total
    assert_select "input[type='number'][data-field='length_cm'][disabled]", count: total
    document = Nokogiri::HTML(response.body)
    rows = document.css("tr[data-profit-prediction-target='row']")
    scenario_tabs = document.css(".profit-prediction-process__scenario-tab[data-profit-prediction-target='scenarioTab']")
    assert_equal total, scenario_tabs.size
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
    wb_rows = rows.select { |row| row["data-platform"] == "wb" && row["data-market"] == "ru" }
    assert wb_rows.all? { |row| row.at_css("input[data-field='return_rate']")["value"].to_d == 10.to_d }
    assert wb_rows.all? { |row| row.at_css("input[data-field='return_rate']")["data-source-value"].to_d == 0.1.to_d }
    wb_belarus_rows = rows.select { |row| row["data-platform"] == "wb" && row["data-market"] == "by" }
    assert_equal 4, wb_belarus_rows.size
    assert wb_belarus_rows.all? { |row| row.at_css("input[data-field='return_rate']")["data-source-value"].to_d == 0.1.to_d }
    assert wb_belarus_rows.all? { |row| row.at_css("input[data-field='acquiring_rate']")["data-source-value"].to_d == 0.019.to_d }
    small_fbo = rows.find do |row|
      row["data-platform"] == "wb" && row["data-company-type"] == "small" && row["data-delivery-mode"] == "fbo"
    end
    assert_equal 1.55.to_d, small_fbo.at_css("input[data-field='logistics_coeff']")["value"].to_d
    ozon_rows = rows.select { |row| row["data-platform"] == "ozon" }
    ozon_fbo_rows = ozon_rows.select { |row| row["data-delivery-mode"] == "fbo" }
    ozon_fbs_rows = ozon_rows.select { |row| row["data-delivery-mode"] == "fbs" }
    assert_equal [ 2, 2 ], [ ozon_fbo_rows.size, ozon_fbs_rows.size ]
    assert_equal 0, rows.count { |row| row["data-actuals-pending"].present? }, "no actual-data kind is platform-wide for a scenario now"
    assert ozon_fbo_rows.all? { |row| row.at_css("input[data-field='warehouse_operation_rub']")["value"].to_d == 25.to_d }
    assert ozon_fbs_rows.all? { |row| row.at_css("input[data-field='fbs_handover_rub']")["value"].to_d == 30.to_d }
    assert ozon_rows.all? { |row| row.at_css("input[data-field='return_rate']")["value"].to_d == 10.to_d }
    assert_select "tr[data-platform='ozon'][data-market='ru'][data-company-type='general']" do
      assert_select "input[type='number'][data-field='commission_base_price_rub']:not([disabled])"
      assert_select "input[type='number'][data-field='buyer_price_vat_rate'][value='22'][data-percent='true'][data-source-value='0.22']"
      assert_select "input[type='number'][data-field='import_vat_rate'][disabled][value='20'][data-source-value='0.2']"
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
    ordered_fields = document.at_css("tr[data-profit-prediction-target='row']").css("[data-field]").map { |input| input["data-field"] }
    assert_operator ordered_fields.index("commission_base_price_rub"), :<, ordered_fields.index("buyer_paid_price_rub")
    assert_operator ordered_fields.index("buyer_paid_price_rub"), :<, ordered_fields.index("buyer_price_vat_rate")
    assert_operator ordered_fields.index("buyer_price_vat_rate"), :<, ordered_fields.index("other_cny")
    assert_select "button[data-action='profit-prediction#save']", text: /Save calculation/
      assert_select ".profit-prediction-process" do
        assert_select "h3", text: "Calculation for selected scenario"
        assert_select ".profit-prediction-process__summary"
        assert_select "[data-profit-prediction-target='detailCommissionBasePrice']"
        assert_select "[data-profit-prediction-target='detailBuyerPaidPrice']"
        assert_select ".profit-prediction-process__summary-item [data-profit-prediction-target='detailPlatformSubsidy']", count: 1
        assert_select "[data-profit-prediction-target='detailTotalCost']"
        assert_select "[data-profit-prediction-target='detailProfit']"
        assert_select "[data-profit-prediction-target='detailMargin']"
        assert_select "[data-profit-prediction-target='detailCostFormula']", count: 1
        assert_select "[data-profit-prediction-target='detailProfitFormula']", count: 1
        assert_select "[data-profit-prediction-target='detailMarginFormula']", count: 1
        assert_select ".profit-prediction-process__status[hidden]", count: 1
        assert_select "th", text: "Item"
        assert_select "th", text: "Parameters"
        assert_select "th.profit-prediction-process__source-head > div > span", text: "Source & shortcuts"
        assert_select "th.profit-prediction-process__source-head button[data-action='profit-prediction#loadAllActuals']",
                      text: "Load all actual data"
        assert_select "th.profit-prediction-process__source-head button[data-action='profit-prediction#loadAndApplyAllActuals']",
                      text: "Load and fill all actual data"
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
    assert_select "td.profit-prediction-table__identity--company_type", text: "一般", count: 8
    assert_select "td.profit-prediction-table__identity--company_type", text: "小规模", count: 4
    assert_select "tr[data-platform='wb'][data-company-type='small'][data-delivery-mode='fbo']" do
      assert_select "input[data-field='wb_logistics_base_rub']"
      assert_select "input[data-field='logistics_tax_rate']"
      assert_select "input[data-field='tax_rate']"
      assert_select "input[type='number'][data-field='wb_fixed_return_base_rub']", count: 0
      assert_select "input[type='number'][data-field='sales_vat_rate']", count: 0
    end
    assert_select "tr[data-platform='ozon'][data-market='by'][data-delivery-mode='fbo']" do
      assert_select "input[data-field='buyer_paid_price_rub']"
      assert_select "input[data-field='commission_base_price_rub']:not([disabled])", count: 1
      assert_select "input[data-field='buyer_price_vat_rate'][value='20'][data-source-value='0.2']"
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
        length_cm width_cm height_cm commission_base_price_rub buyer_paid_price_rub buyer_price_vat_rate exchange_rate_rub_cny commission_rate
        acquiring_rate advertising_rate sales_vat_rate logistics_coeff return_rate
        wb_logistics_base_rub wb_logistics_liter_rub wb_fixed_return_base_rub fbo_delivery_cny storage_cny
        damage_rate misc_cny other_cny outbound_logistics_rub return_logistics_rub
      ],
      ["wb", "small"] => %w[
        purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
        length_cm width_cm height_cm commission_base_price_rub buyer_paid_price_rub buyer_price_vat_rate exchange_rate_rub_cny commission_rate
        acquiring_rate advertising_rate tax_rate logistics_coeff return_rate
        logistics_tax_rate wb_logistics_base_rub wb_logistics_liter_rub fbo_delivery_cny storage_cny
        damage_rate misc_cny other_cny outbound_logistics_rub return_logistics_rub
      ],
      ["ozon", "ru", "fbo"] => %w[
        purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
        length_cm width_cm height_cm commission_base_price_rub buyer_paid_price_rub buyer_price_vat_rate exchange_rate_rub_cny commission_rate
        acquiring_rate advertising_rate other_cny storage_cny return_rate outbound_logistics_rub
        return_logistics_rub warehouse_operation_rub cross_docking_cny
      ],
      ["ozon", "by", "fbo"] => %w[
        purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
        length_cm width_cm height_cm commission_base_price_rub buyer_paid_price_rub buyer_price_vat_rate exchange_rate_rub_cny
        commission_rate acquiring_rate advertising_rate sales_vat_rate other_cny storage_cny return_rate
        outbound_logistics_rub return_logistics_rub warehouse_operation_rub
      ],
      # Seller-shipped: no Ozon warehouse (operation fee, storage, cross-docking), a handover fee instead.
      ["ozon", "ru", "fbs"] => %w[
        purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
        length_cm width_cm height_cm commission_base_price_rub buyer_paid_price_rub buyer_price_vat_rate exchange_rate_rub_cny commission_rate
        acquiring_rate advertising_rate other_cny return_rate outbound_logistics_rub
        return_logistics_rub fbs_handover_rub
      ],
      ["ozon", "by", "fbs"] => %w[
        purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
        length_cm width_cm height_cm commission_base_price_rub buyer_paid_price_rub buyer_price_vat_rate exchange_rate_rub_cny
        commission_rate acquiring_rate advertising_rate sales_vat_rate other_cny return_rate
        outbound_logistics_rub return_logistics_rub fbs_handover_rub
      ]
    }
    document = Nokogiri::HTML(response.body)
    document.css("tr[data-profit-prediction-target='row']").each do |row|
      key = row["data-platform"] == "wb" ? ["wb", row["data-company-type"]] : ["ozon", row["data-market"], row["data-delivery-mode"]]
      actual_fields = row.css("input[type='number'][data-profit-prediction-target~='input']").map { |input| input["data-field"] }
      assert_equal expected_fields.fetch(key).sort, actual_fields.sort, "unexpected input matrix for #{key.join('/')}"
    end
  end

  test "renders a saved draft with inputs ready for direct calculation" do
    version = @sku.profit_versions.create!(name: "Saved draft", status: "draft", effective_from: Date.current)
    version.contexts.create!(
      platform: "wb", market: "ru", delivery_mode: "fbo", company_type: "general",
      purchase_price_cny: 10, length_cm: 10, width_cm: 20, height_cm: 30,
      commission_base_price_rub: 1_000, exchange_rate_rub_cny: 10.123456, logistics_coeff: 1,
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
    assert_select "input[data-field='commission_base_price_rub']:not([disabled])[value='1000.00']"
    assert_select "input[data-field='exchange_rate_rub_cny'][value='10.12'][data-source-value='10.123456']"
    assert_select "input[data-field='commission_rate'][value='7.5'][data-percent='true'][data-source-value='0.075']"
    assert_select "input[data-field='commission_base_price_rub']:not([data-percent])"
    assert_select "td[data-row-status][data-status='valid']", count: 1
    assert_select "td[data-result-field='profit_cny']", text: "12.35"
    assert_select "td[data-result-field='margin']", text: "12.35%"
    assert_select "button[data-action='profit-prediction#save']:not([hidden])"
    assert_includes response.body, "佣金基准价（RUB）"
    assert_includes response.body, "买家实付价（含 VAT，RUB）"
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
        commission_base_price_rub: 15_000, exchange_rate_rub_cny: 13,
        logistics_coeff: 1.55, return_rate: 0.18, wb_logistics_base_rub: 60,
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

  test "returns the current sku WB actual logistics source payload" do
    get report_sku_actual_logistics_path(@sku.sku_code), params: { platform: "wb" }, as: :json

    assert_response :success
    payload = response.parsed_body
    assert_equal "wb", payload.fetch("platform")
    assert_equal 0, payload.fetch("store_count")
    assert_equal 0, payload.dig("outbound", "sample_count")
    assert_nil payload.dig("outbound", "average_rub")
    assert_nil payload.dig("return", "average_rub")
  end

  test "the actual-data endpoints accept the scenario's mode and market and reject what the platform does not have" do
    get report_sku_actual_logistics_path(@sku.sku_code), params: { platform: "wb", delivery_mode: "fbs", market: "by" }, as: :json
    assert_response :success
    assert_equal [ "fbs", "by" ], response.parsed_body.values_at("delivery_mode", "market")

    sign_in @user
    get report_sku_actual_logistics_path(@sku.sku_code), params: { platform: "ozon", delivery_mode: "fbs" }, as: :json
    assert_response :success
    assert_equal "fbs", response.parsed_body.fetch("delivery_mode")
    assert_equal 0, response.parsed_body.dig("handover", "sample_count")

    sign_in @user
    get report_sku_actual_return_rate_path(@sku.sku_code), params: { platform: "wb", delivery_mode: "fbo", market: "ru" }, as: :json
    assert_response :success

    sign_in @user
    get report_sku_actual_acquiring_path(@sku.sku_code), params: { platform: "ozon", delivery_mode: "fbs" }, as: :json
    assert_response :success
    assert_equal "fbs", response.parsed_body.fetch("delivery_mode")

    sign_in @user
    get report_sku_actual_selling_price_path(@sku.sku_code), params: { platform: "wb", market: "by", delivery_mode: "fbs" }, as: :json
    assert_response :success
    assert_equal "fbs", response.parsed_body.fetch("delivery_mode")

    sign_in @user
    get report_sku_actual_storage_path(@sku.sku_code), params: { platform: "ozon", delivery_mode: "fbo" }, as: :json
    assert_response :success

    sign_in @user
    get report_sku_actual_storage_path(@sku.sku_code), params: { platform: "ozon", delivery_mode: "dbs" }, as: :json
    assert_response :unprocessable_entity

    sign_in @user
    get report_sku_actual_logistics_path(@sku.sku_code), params: { platform: "ozon", market: "by" }, as: :json
    assert_response :unprocessable_entity
    assert_equal [ "unsupported_market" ], response.parsed_body.fetch("errors")

    sign_in @user
    get report_sku_actual_acquiring_path(@sku.sku_code), params: { platform: "wb", market: "kz" }, as: :json
    assert_response :unprocessable_entity

    sign_in @user
    get report_sku_actual_selling_price_path(@sku.sku_code), params: { platform: "wb", market: "ru", delivery_mode: "dbs" }, as: :json
    assert_response :unprocessable_entity
    assert_equal [ "unsupported_delivery_mode" ], response.parsed_body.fetch("errors")
  end

  test "rejects unsupported actual logistics platforms" do
    get report_sku_actual_logistics_path(@sku.sku_code), params: { platform: "other" }, as: :json

    assert_response :unprocessable_entity
    assert_equal ["unsupported_platform"], response.parsed_body.fetch("errors")
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
    assert_equal "RUB", payload.dig("buyer_paid_price", "source_currency")
    assert_equal 0, payload.dig("buyer_paid_price", "item_count")
    assert_nil payload.dig("buyer_paid_price", "average_rub")
    assert_equal 0, payload.dig("commission_base_price", "item_count")
    assert_nil payload.dig("commission_base_price", "average_rub")
    assert_not payload.key?("price")
    assert_not payload.key?("seller_price")
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

  test "returns the current sku actual acquiring payload for the requested platform" do
    get report_sku_actual_acquiring_path(@sku.sku_code), params: { platform: "wb" }, as: :json

    assert_response :success
    payload = response.parsed_body
    assert_equal "wb", payload.fetch("platform")
    assert_equal 0, payload.dig("acquiring", "sample_count")
    assert_nil payload.dig("acquiring", "rate")
  end

  test "rejects unsupported actual acquiring platforms" do
    get report_sku_actual_acquiring_path(@sku.sku_code), params: { platform: "amazon" }, as: :json

    assert_response :unprocessable_entity
    assert_equal ["unsupported_platform"], response.parsed_body.fetch("errors")
  end

  test "sets one current version per SKU and rejects what cannot be current" do
    older = @sku.profit_versions.create!(name: "older", status: "draft", effective_from: Date.new(2026, 9, 1))
    newer = @sku.profit_versions.create!(name: "newer", status: "draft", effective_from: Date.new(2026, 10, 1))
    archived = @sku.profit_versions.create!(name: "archived", status: "archived", effective_from: Date.new(2026, 8, 1))

    patch set_current_report_sku_profit_version_path(@sku.sku_code, older), as: :json
    assert_response :success
    assert_equal({ "id" => older.id, "is_current" => true }, response.parsed_body)

    sign_in @user
    patch set_current_report_sku_profit_version_path(@sku.sku_code, newer), as: :json
    assert_response :success
    assert_equal [ newer.id ], @sku.profit_versions.current.pluck(:id)
    assert_not older.reload.is_current

    sign_in @user
    patch set_current_report_sku_profit_version_path(@sku.sku_code, archived), as: :json
    assert_response :unprocessable_entity
    assert response.parsed_body.fetch("errors").key?("status")
    assert_equal [ newer.id ], @sku.profit_versions.current.pluck(:id)

    other_sku = Ec::Sku.create!(sku_code: "PVO-#{SecureRandom.hex(4).upcase}")
    foreign = other_sku.profit_versions.create!(name: "foreign", status: "draft", effective_from: Date.new(2026, 10, 1))
    begin
      sign_in @user
      patch set_current_report_sku_profit_version_path(@sku.sku_code, foreign), as: :json
      assert_response :not_found
      assert_not foreign.reload.is_current
    ensure
      Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: foreign.id).delete_all
      foreign.destroy
      Ec::OperationLog.where(record_type: "Ec::Sku", record_id: other_sku.id).delete_all
      other_sku.destroy
    end
  end

  test "setting the current version needs the manage SKUs permission" do
    version = @sku.profit_versions.create!(name: "v", status: "draft", effective_from: Date.new(2026, 10, 1))
    reader = create_user_with_roles("reader-#{SecureRandom.hex(4)}@example.com", "auditor")
    sign_in reader

    patch set_current_report_sku_profit_version_path(@sku.sku_code, version), as: :json

    assert_response :forbidden
    assert_not version.reload.is_current
  ensure
    UserRole.where(user_id: reader&.id).delete_all
    User.where(id: reader&.id).delete_all
  end

  test "the tab opens the current version and marks it, with a way to set another one" do
    older = @sku.profit_versions.create!(name: "Older model", status: "draft", effective_from: Date.new(2026, 9, 1))
    newer = @sku.profit_versions.create!(name: "Newer model", status: "draft", effective_from: Date.new(2026, 10, 1))
    older.make_current!

    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".profit-prediction-workbench[data-profit-prediction-version-id-value='#{older.id}']"
    assert_select ".profit-prediction-workbench[data-profit-prediction-set-current-url-value='#{set_current_report_sku_profit_version_path(@sku.sku_code, older)}']"
    assert_select ".profit-prediction-version-switcher option[selected]", text: "Older model · Current · Draft"
    assert_select ".profit-prediction-version-switcher option", text: "Newer model · Draft"
    assert_select ".profit-prediction-version-switcher option:first-child", text: "Older model · Current · Draft"
    assert_select ".profit-prediction-current-badge", text: /Current version/
    assert_select "button[data-action='profit-prediction#setCurrent']", count: 0
    assert_select ".profit-prediction-alert--info", count: 0

    sign_in @user
    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", locale: "en", version_id: newer.id }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".profit-prediction-current-badge", count: 0
    assert_select ".profit-prediction-toolbar button[data-action='profit-prediction#setCurrent']", text: /Set as current version/
    assert_select ".profit-prediction-alert--info", text: /not looking at the current version/
  end

  test "a saved version opens with the neutral saved status, an unsaved new one with the dirty status" do
    @sku.profit_versions.create!(name: "Saved", status: "draft", effective_from: Date.new(2026, 10, 1))

    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", locale: "en" }, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select ".profit-prediction-mode-status:not(.is-dirty)", text: "Saved"

    sign_in @user
    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", locale: "en", new_profit_version: 1 }, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select ".profit-prediction-mode-status.is-dirty"
  end

  test "the tab offers the calculator and the table as two views, calculator first, with both kept in the page" do
    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".profit-prediction-workbench[data-view-mode='calculator']"
    assert_select ".profit-prediction-toolbar__identity .profit-prediction-view-tabs[role='tablist'] .profit-prediction-view-tab", count: 2
    # The switch lives in the title row, right after the save status, not in a row of its own.
    assert_select ".profit-prediction-toolbar__identity > .profit-prediction-toolbar__statuses + .profit-prediction-view-tabs"
    assert_select ".profit-prediction-view-tab.is-active[data-view-mode='calculator']", text: "Scenario calculator"
    assert_select ".profit-prediction-view-tab[data-view-mode='table'][aria-selected='false']", text: "Scenario table"
    assert_select "[data-profit-prediction-target='tableView'][hidden]"
    assert_select "[data-profit-prediction-target='calculatorView']:not([hidden])"
    # The calculator reads the table's inputs, so the table must stay in the page even when hidden.
    assert_select "[data-profit-prediction-target='tableView'] .profit-prediction-table tbody tr[data-profit-prediction-target~='row']", minimum: Ec::SkuProfitStandardContexts::SCENARIOS.size
    assert_select "[data-profit-prediction-target='tableView'] .profit-prediction-platform-tab", count: 3
    assert_select "[data-profit-prediction-target='calculatorView'] .profit-prediction-process__scenario-tab", count: Ec::SkuProfitStandardContexts::SCENARIOS.size
  end

  test "an unsaved new version offers no way to set it as current" do
    @sku.profit_versions.create!(name: "Saved", status: "draft", effective_from: Date.new(2026, 10, 1)).make_current!

    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", locale: "en", new_profit_version: 1 }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "button[data-action='profit-prediction#setCurrent']", count: 0
    assert_select ".profit-prediction-current-badge", count: 0
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
      commission_base_price_rub: 1_000, exchange_rate_rub_cny: 10, logistics_coeff: 1,
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

  test "creating with copy_from_version_id copies that version under the given name, with every standard scenario" do
    source = @sku.profit_versions.new(name: "Source", status: "draft", effective_from: Date.new(2026, 9, 1))
    source.contexts.build(
      platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
      purchase_price_cny: 42, commission_base_price_rub: 1_234, commission_rate: 0.1, exchange_rate_rub_cny: 10,
      length_cm: 10, width_cm: 10, height_cm: 10, logistics_coeff: 1, return_rate: 0.1
    )
    source.save!

    post report_sku_profit_versions_path(@sku.sku_code), params: {
      version: { name: "Autumn prices", status: "draft", effective_from: "2026-10-20" }, copy_from_version_id: source.id
    }, as: :json

    assert_response :created
    copy = @sku.profit_versions.find(response.parsed_body.fetch("id"))
    assert_equal "Autumn prices", copy.name
    assert_equal "draft", copy.status
    assert_not copy.is_current
    assert_equal Date.new(2026, 10, 20), copy.effective_from
    assert_equal Ec::SkuProfitStandardContexts::SCENARIOS.size, copy.contexts.count
    copied = copy.contexts.find_by!(platform: "wb", market: "ru", delivery_mode: "fbo", company_type: "general")
    assert_equal 1_234.to_d, copied.commission_base_price_rub
    assert_equal 42.to_d, copied.purchase_price_cny
    assert_equal 1, source.reload.contexts.count, "the source is untouched"
  end

  test "copying a version of another SKU is refused" do
    other = Ec::Sku.create!(sku_code: "PVX-#{SecureRandom.hex(4).upcase}")
    foreign = other.profit_versions.create!(name: "Foreign", status: "draft", effective_from: Date.new(2026, 9, 1))

    post report_sku_profit_versions_path(@sku.sku_code), params: {
      version: { name: "Stolen", status: "draft", effective_from: "2026-10-20" }, copy_from_version_id: foreign.id
    }, as: :json

    assert_response :not_found
    assert_equal 0, @sku.profit_versions.where(name: "Stolen").count
  ensure
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: foreign&.id).delete_all
    foreign&.destroy
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: other&.id).delete_all
    other&.destroy
  end

  test "deleting a version removes it with its scenarios and logs it" do
    version = @sku.profit_versions.new(name: "To delete", status: "draft", effective_from: Date.new(2026, 9, 1))
    Ec::SkuProfitStandardContexts::SCENARIOS.first(3).each { |scenario| version.contexts.build(scenario) }
    version.save!
    context_ids = version.contexts.pluck(:id)

    delete report_sku_profit_version_path(@sku.sku_code, version), as: :json

    assert_response :success
    assert_equal({ "id" => version.id, "deleted" => true }, response.parsed_body)
    assert_not Ec::SkuProfitVersion.exists?(version.id)
    assert_empty Ec::SkuProfitVersionContext.where(id: context_ids)
    assert Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: version.id, action: "destroy").exists?
  end

  test "the current version cannot be deleted" do
    version = @sku.profit_versions.create!(name: "Current", status: "draft", effective_from: Date.new(2026, 9, 1))
    version.make_current!

    delete report_sku_profit_version_path(@sku.sku_code, version), as: :json

    assert_response :unprocessable_entity
    assert_equal [ "current_version" ], response.parsed_body.dig("errors", "base")
    assert Ec::SkuProfitVersion.exists?(version.id)
  end

  test "a version of another SKU cannot be deleted through this SKU" do
    other = Ec::Sku.create!(sku_code: "PVD-#{SecureRandom.hex(4).upcase}")
    foreign = other.profit_versions.create!(name: "Foreign", status: "draft", effective_from: Date.new(2026, 9, 1))

    delete report_sku_profit_version_path(@sku.sku_code, foreign), as: :json

    assert_response :not_found
    assert Ec::SkuProfitVersion.exists?(foreign.id)
  ensure
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: foreign&.id).delete_all
    foreign&.destroy
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: other&.id).delete_all
    other&.destroy
  end

  test "deleting a version needs the manage SKUs permission" do
    version = @sku.profit_versions.create!(name: "Guarded", status: "draft", effective_from: Date.new(2026, 9, 1))
    reader = create_user_with_roles("reader-#{SecureRandom.hex(4)}@example.com", "auditor")
    sign_in reader

    delete report_sku_profit_version_path(@sku.sku_code, version), as: :json

    assert_response :forbidden
    assert Ec::SkuProfitVersion.exists?(version.id)
  ensure
    UserRole.where(user_id: reader&.id).delete_all
    User.where(id: reader&.id).delete_all
  end

  test "the delete button sits after save, in danger style, and is disabled on the current version" do
    current = @sku.profit_versions.create!(name: "Current", status: "draft", effective_from: Date.new(2026, 9, 1))
    current.make_current!
    other = @sku.profit_versions.create!(name: "Other", status: "draft", effective_from: Date.new(2026, 10, 1))

    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", version_id: other.id, locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".profit-prediction-toolbar__calculation-actions .btn-primary + .btn-danger[data-action='profit-prediction#openDeleteDialog']:not([disabled])", text: /Delete version/
    assert_select "[data-profit-prediction-delete-url-value='#{report_sku_profit_version_path(@sku.sku_code, other)}']"
    assert_select "dialog[data-profit-prediction-target='deleteDialog'] .btn-danger[data-action='profit-prediction#submitDeleteDialog']", count: 1

    sign_in @user
    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", version_id: current.id, locale: "en" }, headers: { "Accept" => "text/html" }
    assert_select ".profit-prediction-toolbar__calculation-actions .btn-danger[disabled][title]", count: 1
  end

  test "an unsaved new version has no delete button" do
    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", new_profit_version: 1, locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "[data-action='profit-prediction#openDeleteDialog']", count: 0
  end

  test "a saved version made before the new scenarios opens with them added, unsaved" do
    version = @sku.profit_versions.new(name: "Old", status: "draft", effective_from: Date.current)
    Ec::SkuProfitStandardContexts::SCENARIOS.first(6).each { |scenario| version.contexts.build(scenario) }
    version.save!

    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", version_id: version.id, locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    rows = Nokogiri::HTML(response.body).css("tr[data-profit-prediction-target='row']")
    assert_equal Ec::SkuProfitStandardContexts::SCENARIOS.size, rows.size
    assert_equal 6, rows.count { |row| row["data-context-id"].to_s.empty? }
    assert_equal 6, version.reload.contexts.count, "opening the page writes nothing"
  end

  test "scenarios added to an old version, and to a new one, start at the price the SKU really sold them for" do
    account = RawOzon::SellerAccount.create!(client_id: "prefill-#{SecureRandom.hex(4)}", api_key: "key", company_name: "Prefill", company_type: "general")
    store = Ec::Store.create!(platform: "ozon", store_name: "Prefill #{SecureRandom.hex(3)}", company_type: "general", ozon_raw_account_id: account.id)
    product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: store, product_id: "pf-#{SecureRandom.hex(3)}", platform_sku_id: "98765#{SecureRandom.random_number(1000)}")
    6.times do |index|
      order = Ec::Order.create!(store:, platform: "ozon", order_key: "ozon:#{store.id}:pf-#{index}-#{SecureRandom.hex(3)}", order_status: "delivered", ordered_at: 3.weeks.ago)
      fulfillment = Ec::OrderFulfillment.create!(order:, store:, platform: "ozon", fulfillment_type: "fbs", status: "delivered",
        external_fulfillment_id: "pf-f-#{index}-#{SecureRandom.hex(3)}", fulfillment_key: "pf-f-#{index}-#{SecureRandom.hex(3)}")
      Ec::OrderItem.create!(order:, store:, platform: "ozon", platform_sku_id: product.platform_sku_id, quantity: 1, unit_price: 3_000 + index * 100,
        currency_code: "RUB", buyer_paid_unit_price: 2_900, buyer_currency_code: "RUB", fulfillment_id: fulfillment.id)
    end
    old = @sku.profit_versions.new(name: "Old", status: "draft", effective_from: Date.current)
    Ec::SkuProfitStandardContexts::SCENARIOS.first(2).each { |scenario| old.contexts.build(scenario) }
    old.save!

    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", version_id: old.id, locale: "en" }, headers: { "Accept" => "text/html" }
    assert_response :success
    rows = Nokogiri::HTML(response.body).css("tr[data-profit-prediction-target='row']")
    fbs = rows.find { |row| row["data-platform"] == "ozon" && row["data-delivery-mode"] == "fbs" && row["data-market"] == "ru" }
    assert_equal 3_250.to_d, fbs.at_css("input[data-field='commission_base_price_rub']")["value"].to_d, "(3000..3500 step 100) over 6 units"
    assert_empty rows.select { |row| row["data-platform"] == "wb" && row["data-market"] == "by" }.map { |row| row.at_css("input[data-field='commission_base_price_rub']")["value"].presence }.compact,
      "nothing sold there, so no price"

    sign_in @user
    post report_sku_profit_versions_path(@sku.sku_code), params: { version: { name: "Fresh", status: "draft", effective_from: Date.current.to_s } }, as: :json
    assert_response :created
    created = response.parsed_body.fetch("contexts").find { |context| context["platform"] == "ozon" && context["delivery_mode"] == "fbs" && context["market"] == "ru" }
    assert_equal 3_250.to_d, created.fetch("commission_base_price_rub").to_d
  ensure
    Ec::OrderItem.where(store_id: store&.id).delete_all
    Ec::OrderFulfillment.where(store_id: store&.id).delete_all
    Ec::Order.where(store_id: store&.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: product&.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: store&.id).delete_all
    Ec::SkuProduct.where(id: product&.id).delete_all
    Ec::Store.where(id: store&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "the logistics mode of a scenario is saved, returned, copied and checked" do
    version = @sku.profit_versions.create!(name: "Modes", status: "draft", effective_from: Date.current)
    wb = version.contexts.create!(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general")
    assert_equal "formula", wb.logistics_mode, "a new scenario starts on the fixed formula"

    patch report_sku_profit_version_path(@sku.sku_code, version), params: {
      version: { lock_version: version.lock_version },
      contexts: [ { id: wb.id, platform: "wb", market: "ru", delivery_mode: "fbo", logistics_mode: "actual", inputs: { outbound_logistics_rub: "250" } } ]
    }, as: :json

    assert_response :success
    assert_equal "actual", wb.reload.logistics_mode
    payload_context = response.parsed_body.fetch("contexts").find { |context| context["id"] == wb.id }
    assert_equal "actual", payload_context.fetch("logistics_mode")
    assert_equal 250.to_d, payload_context.fetch("outbound_logistics_rub").to_d

    sign_in @user
    post report_sku_profit_versions_path(@sku.sku_code), params: {
      version: { name: "Copy", status: "draft", effective_from: Date.current.to_s }, copy_from_version_id: version.id
    }, as: :json
    assert_response :created
    copied = response.parsed_body.fetch("contexts").find { |context| context["platform"] == "wb" && context["market"] == "ru" && context["delivery_mode"] == "fbo" }
    assert_equal "actual", copied.fetch("logistics_mode")
    assert_equal "formula", response.parsed_body.fetch("contexts").find { |context| context["platform"] == "ozon" && context["delivery_mode"] == "fbs" }.fetch("logistics_mode"),
      "a scenario added by the copy starts on the formula"

    sign_in @user
    patch report_sku_profit_version_path(@sku.sku_code, version.reload), params: {
      version: { lock_version: version.lock_version },
      contexts: [ { id: wb.id, platform: "wb", market: "ru", delivery_mode: "fbo", logistics_mode: "guess" } ]
    }, as: :json
    assert_response :unprocessable_entity
    assert_equal "actual", wb.reload.logistics_mode
  end

  test "the preview takes the mode from the scenario and returns both modes' figures" do
    post preview_report_sku_profit_path(@sku.sku_code), params: {
      platform: "wb", parameter_context: { market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general", logistics_mode: "formula" },
      inputs: { commission_base_price_rub: "4000", commission_rate: "0.2", exchange_rate_rub_cny: "13", return_rate: "0.1", outbound_logistics_rub: "999" }
    }, as: :json

    assert_response :success
    logistics = response.parsed_body.fetch("logistics")
    assert_equal "formula", logistics.fetch("mode")
    assert_equal "actual", logistics.dig("alternative", "mode")
    assert_equal "coefficient", response.parsed_body.dig("intermediate", "logistics_source")
    assert_equal 50, logistics.dig("formula", "return_rub").to_d
  end

  test "an archived version keeps exactly the scenarios it had" do
    version = @sku.profit_versions.new(name: "Archived", status: "archived", effective_from: Date.new(2026, 1, 1), effective_to: Date.new(2026, 1, 31))
    Ec::SkuProfitStandardContexts::SCENARIOS.first(2).each { |scenario| version.contexts.build(scenario) }
    version.save!

    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", version_id: version.id, locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "tr[data-profit-prediction-target='row']", count: 2
  end

  test "saving a version writes the scenarios that were added to it" do
    version = @sku.profit_versions.create!(name: "Draft", status: "draft", effective_from: Date.current)
    version.contexts.create!(platform: "wb", market: "ru", delivery_mode: "fbo", company_type: "general")

    patch report_sku_profit_version_path(@sku.sku_code, version), params: {
      version: { lock_version: version.lock_version },
      contexts: [
        { platform: "ozon", market: "ru", delivery_mode: "fbs", warehouse_region: "main", company_type: "general", logistics_mode: "actual",
          inputs: { commission_base_price_rub: "3000", commission_rate: "0.4", outbound_logistics_rub: "250", return_logistics_rub: "150",
                    purchase_price_cny: "50", length_cm: "10", width_cm: "10", height_cm: "10", fbs_handover_rub: "28" } }
      ]
    }, as: :json

    assert_response :success
    created = version.reload.contexts.find_by!(platform: "ozon", delivery_mode: "fbs")
    assert_equal 28.to_d, created.fbs_handover_rub
    assert_equal "valid", created.calculation_status
    assert_equal 2, version.contexts.count
  end

  test "a published version can be saved while a hidden scenario is still incomplete" do
    version = @sku.profit_versions.new(name: "Published", status: "published", effective_from: Date.current)
    version.contexts.build(
      platform: "wb", market: "ru", delivery_mode: "fbo", company_type: "general",
      purchase_price_cny: 10, length_cm: 10, width_cm: 20, height_cm: 30,
      commission_base_price_rub: 1_000, exchange_rate_rub_cny: 10, logistics_coeff: 1,
      return_rate: 0.1, commission_rate: 0.1
    )
    version.save!
    incomplete = { platform: "wb", market: "by", delivery_mode: "fbs", warehouse_region: "main", company_type: "small" }

    patch report_sku_profit_version_path(@sku.sku_code, version), params: {
      version: { lock_version: version.lock_version }, contexts: [ incomplete ]
    }, as: :json
    assert_response :unprocessable_entity, "an incomplete shown scenario still blocks a published version"

    Ec::SkuScenarioVisibility.set!(sku: @sku, identity: incomplete.stringify_keys, hidden: true, user: @user)
    sign_in @user
    patch report_sku_profit_version_path(@sku.sku_code, version.reload), params: {
      version: { lock_version: version.lock_version }, contexts: [ incomplete ]
    }, as: :json

    assert_response :success
    assert_equal 2, version.reload.contexts.count
  end

  private

  def valid_wb_profit_inputs
    {
      commission_base_price_rub: 1_000,
      exchange_rate_rub_cny: 10,
      logistics_coeff: 1.2,
      return_rate: 0.2,
      commission_rate: 0.12
    }
  end
end
