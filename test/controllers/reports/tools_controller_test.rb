require "test_helper"

class ReportsToolsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("reports-tools-#{@token.downcase}@example.com", "auditor")
    sign_in @current_user
    @definition_creator = User.create!(
      email: "reports-tools-owner-#{@token.downcase}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  teardown do
    Ec::ToolConfiguration.where("name LIKE ?", "%#{@token}%").delete_all if defined?(Ec::ToolConfiguration)
    Ec::ToolConfiguration.joins(:tool_definition).where(ec_tool_definitions: { tool_type: ["wb_pallet_optimizer", "roi_calculator", "smart_pack_calculator"] }).delete_all if defined?(Ec::ToolConfiguration)
    Ec::ToolDefinition.where("tool_type LIKE ?", "%#{@token}%").delete_all if defined?(Ec::ToolDefinition)
    Ec::ToolDefinition.where(tool_type: ["wb_pallet_optimizer", "roi_calculator", "smart_pack_calculator"]).delete_all if defined?(Ec::ToolDefinition)
    UserRole.joins(:user).where("users.email LIKE ?", "reports-tools-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "reports-tools-%#{@token.downcase}@example.com").delete_all
    User.where(id: @definition_creator.id).delete_all if @definition_creator
  end

  test "index renders tool configuration library" do
    definition = Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 1,
      name: "WB Pallet #{@token}",
      slug: "wb-pallet-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      created_by: @definition_creator
    )
    Ec::ToolConfiguration.create!(
      tool_definition: definition,
      name: "WB Config #{@token}",
      config_json: { "exchange" => "12" },
      created_by: @definition_creator
    )

    get "/reports/tools", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1.page-title", "测算工具"
    assert_select ".report-stack.report-tools-index"
    assert_select "p.report-meta", "共享测算配置库"
    assert_select ".resource-header.report-tools-index__header"
    assert_select ".resource-header.report-tools-index__header .resource-actions a[href='/reports/tools/new'][data-turbo-frame='erp_modal']", text: "打开工具"
    assert_select ".report-tools-index__filters.panel"
    assert_select ".report-tools-index__history.panel"
    assert_select "h2.section-title", "测算历史"
    assert_select "td", "WB Config #{@token}"
    assert_select "th", "操作"
    assert_select "turbo-frame#erp_modal"
    assert_select "turbo-frame#tool_drawer"
    assert_select "form[action='/reports/tools'][method='get']"
    assert_select "form.report-form"
    assert_select "form.report-form a[href='/reports/tools/new'][data-turbo-frame='erp_modal']", count: 0
    assert_select "input[name='q']"
    assert_select "select[name='tool_type']"
    assert_select "input[name='version']"
    assert_select "input[name='creator']"
    assert_select ".table-scroll"
    assert_select "table.inventory-list-table.report-tools-table"
    assert_select "form.button_to[action='#{report_tool_configuration_path(Ec::ToolConfiguration.find_by!(name: "WB Config #{@token}"))}'] button", text: "删除", count: 0
    assert_select ".store-management", count: 0
    assert_select ".prod-tbl", count: 0
    assert_select "a[href='#{report_tool_configuration_path(Ec::ToolConfiguration.find_by!(name: "WB Config #{@token}"))}'][data-turbo-frame='tool_drawer']"
    assert_select "a[href='#{report_tool_configuration_path(Ec::ToolConfiguration.find_by!(name: "WB Config #{@token}"))}'][data-turbo-action='replace']", count: 0
  end

  test "index filters tool configuration history" do
    wb_definition = Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 3,
      name: "WB Pallet #{@token}",
      slug: "wb-pallet-filter-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      created_by: @definition_creator
    )
    roi_definition = Ec::ToolDefinition.create!(
      tool_type: "roi_calculator_#{@token}",
      version: 2,
      name: "ROI Calculator #{@token}",
      slug: "roi-filter-#{@token.downcase}",
      renderer_key: "roi_calculator_v1",
      created_by: @definition_creator
    )
    Ec::ToolConfiguration.create!(
      tool_definition: wb_definition,
      name: "WB Config #{@token}",
      config_json: { "exchange" => "12" },
      created_by: @definition_creator
    )
    Ec::ToolConfiguration.create!(
      tool_definition: roi_definition,
      name: "ROI Config #{@token}",
      config_json: { "cost" => "400" },
      created_by: @current_user
    )

    get "/reports/tools",
      params: {
        q: "ROI Config #{@token}",
        tool_type: "roi_calculator_#{@token}",
        version: "2",
        creator: @current_user.email
      },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", "ROI Config #{@token}"
    assert_select "td", text: "WB Config #{@token}", count: 0
    assert_select "input[name='q'][value='ROI Config #{@token}']"
    assert_select "select[name='tool_type'] option[selected][value='roi_calculator_#{@token}']"
    assert_select "input[name='version'][value='2']"
    assert_select "input[name='creator'][value='#{@current_user.email}']"
  end

  test "index shows delete action only for current user's configurations" do
    own_definition = Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_own_#{@token}",
      version: 1,
      name: "WB Own #{@token}",
      slug: "wb-own-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      created_by: @current_user
    )
    other_definition = Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_other_#{@token}",
      version: 1,
      name: "WB Other #{@token}",
      slug: "wb-other-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      created_by: @definition_creator
    )
    own_configuration = Ec::ToolConfiguration.create!(
      tool_definition: own_definition,
      name: "Own Config #{@token}",
      config_json: { "exchange" => "12" },
      created_by: @current_user
    )
    other_configuration = Ec::ToolConfiguration.create!(
      tool_definition: other_definition,
      name: "Other Config #{@token}",
      config_json: { "exchange" => "13" },
      created_by: @definition_creator
    )

    get "/reports/tools", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "form.button_to[action='#{report_tool_configuration_path(own_configuration)}'] button.btn-danger.link-button", text: "删除"
    assert_select "form.button_to[action='#{report_tool_configuration_path(other_configuration)}']", count: 0
  end

  test "index preloads drawer from shared configuration url" do
    definition = Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 1,
      name: "WB Pallet #{@token}",
      slug: "wb-pallet-share-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      created_by: @definition_creator
    )
    configuration = Ec::ToolConfiguration.create!(
      tool_definition: definition,
      name: "WB Config #{@token}",
      config_json: { "exchange" => "12" },
      created_by: @definition_creator
    )

    get "/reports/tools", params: { tool_configuration_id: configuration.id }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "turbo-frame#tool_drawer[src='#{report_tool_configuration_path(configuration)}']"
  end

  test "tool type route opens latest active version" do
    Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 1,
      name: "WB Pallet Old #{@token}",
      slug: "wb-pallet-old-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      active: false,
      created_by: @definition_creator
    )
    Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 2,
      name: "WB Pallet New #{@token}",
      slug: "wb-pallet-new-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      active: true,
      created_by: @definition_creator
    )

    get "/reports/tools/wb_pallet_optimizer_#{@token}", headers: { "Accept" => "text/html" }

    assert_redirected_to "/reports/tools/wb_pallet_optimizer_#{@token}/versions/2"
  end

  test "version route renders tool page" do
    Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 2,
      name: "WB Pallet New #{@token}",
      slug: "wb-pallet-show-definition-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      active: true,
      created_by: @definition_creator
    )

    get "/reports/tools/wb_pallet_optimizer_#{@token}/versions/2", headers: { "Accept" => "text/html", "Turbo-Frame" => "tool_drawer" }

    assert_response :success
    assert_select "turbo-frame#tool_drawer"
    assert_select ".inventory-drawer.inventory-drawer--full.inventory-drawer--header-sm[data-close-path='/reports/tools'][style*='width: 90vw'][style*='max-width: 90vw'][style*='flex-basis: 90vw']"
    assert_select "[data-tool-type='wb_pallet_optimizer_#{@token}'][data-tool-version='2'][data-tool-share-path='/reports/tools?tool_type=wb_pallet_optimizer_#{@token}&version=2'].tool-renderer-page--full"
    assert_select ".wb-tool-inline"
    assert_select ".wb-tool-shell.wb-tool-shell--full"
    assert_select ".wb-tool-shell__sidebar", count: 0
    assert_select "iframe", count: 0
    assert_select "#input_form"
    assert_select "#exchange"
    assert_select ".inventory-drawer__header button", text: "保存配置"
    assert_select ".inventory-drawer__header button", text: "另存为", count: 0
    assert_select "[data-tool-save-name-modal]", count: 1
    assert_select "input[data-tool-save-name-input][name='tool_configuration_name']"
    assert_includes response.body, 'data-modal-close-path-value="/reports/tools"'
    assert_not_includes response.body, "data-modal-close-path-value=&quot;/reports/tools&quot;"
    assert_not_includes response.body, 'data-tool-host-target="library"'
    assert_not_includes response.body, 'link.dataset.turboAction = "replace";'
    assert_includes response.body, "parentFrame.src = body.show_path;"
    assert_includes response.body, 'const drawer = page.closest(".inventory-drawer");'
    assert_includes response.body, 'const saveButton = drawer?.querySelector("[data-tool-action=\'save\']");'
    assert_includes response.body, "const openSaveNameModal = ({"
    assert_includes response.body, "saveButton?.addEventListener(\"click\", () => {"
    assert_includes response.body, 'const sharePath = page.dataset.toolSharePath;'
    assert_includes response.body, 'window.history.replaceState(window.history.state, "", sharePath);'
    assert_includes response.body, "window.restoreState(configuration.config_json);"
    assert_includes response.body, "window.calculateAll();"
    assert_includes response.body, 'drawer?.addEventListener("animationend", runStabilizedRefresh, { once: true });'
    assert_includes response.body, 'window.dispatchEvent(new Event("resize"));'
    assert_includes response.body, "if (typeof refreshWbCharts !== 'undefined') window.refreshWbCharts = refreshWbCharts;"
    assert_includes response.body, '[0, 120, 260, 420].forEach((delay) => {'
    assert_includes response.body, 'setTimeout(() => {'
    assert_includes response.body, 'window.refreshWbCharts?.();'
    assert_not_includes response.body, "const syncIframeHeight = () => {"
    assert_not_includes response.body, "new ResizeObserver(() => {"
    assert_not_includes response.body, 'iframe.style.height = `${nextHeight}px`;'
    assert_not_includes response.body, 'window.Turbo.visit(body.show_path, { frame: "tool_drawer"'
    assert_not_includes response.body, 'window.Turbo.visit(body.show_path, { frame: "tool_drawer", action: "replace" });'
  end

  test "tool type route falls back to latest version when no active version exists" do
    Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 1,
      name: "WB Pallet Old #{@token}",
      slug: "wb-pallet-old-fallback-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      active: false,
      created_by: @definition_creator
    )
    Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 3,
      name: "WB Pallet New #{@token}",
      slug: "wb-pallet-new-fallback-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      active: false,
      created_by: @definition_creator
    )

    get "/reports/tools/wb_pallet_optimizer_#{@token}", headers: { "Accept" => "text/html" }

    assert_redirected_to "/reports/tools/wb_pallet_optimizer_#{@token}/versions/3"
  end

  test "new renders selectable tool dropdown" do
    Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 1,
      name: "WB Pallet #{@token}",
      slug: "wb-pallet-new-page-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      created_by: @definition_creator
    )
    Ec::ToolDefinition.create!(
      tool_type: "roi_calculator_#{@token}",
      version: 1,
      name: "ROI Calculator #{@token}",
      slug: "roi-calculator-new-page-#{@token.downcase}",
      renderer_key: "roi_calculator_v1",
      created_by: @definition_creator
    )

    get "/reports/tools/new", headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "打开工具"
    assert_select "select[name='tool_path'] option", minimum: 2
    assert_select "select[name='tool_path'] option[value='/reports/tools/wb_pallet_optimizer_#{@token}']", "WB Pallet #{@token}"
    assert_select "select[name='tool_path'] option[value='/reports/tools/roi_calculator_#{@token}']", "ROI Calculator #{@token}"
    assert_select "a[data-tool-open-link][data-turbo-frame='tool_drawer'][data-action='click->modal#close']", text: "打开工具"
    assert_includes response.body, "data-tool-picker-root"
    assert_includes response.body, "this.closest(&#39;[data-tool-picker-root]&#39;).querySelector(&quot;select[name=&#39;tool_path&#39;]&quot;).value"
    assert_select "table", count: 0
  end

  test "renderer source serves the original wb pallet optimizer html" do
    get "/reports/tools/renderers/wb_pallet_optimizer_v1/source", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_includes response.body, "WB平台送仓计算器"
    assert_includes response.body, "function calculateAll()"
  end

  test "roi tool type route opens latest active version" do
    Ec::ToolDefinition.create!(
      tool_type: "roi_calculator_#{@token}",
      version: 1,
      name: "ROI Old #{@token}",
      slug: "roi-old-#{@token.downcase}",
      renderer_key: "roi_calculator_v1",
      active: false,
      created_by: @definition_creator
    )
    Ec::ToolDefinition.create!(
      tool_type: "roi_calculator_#{@token}",
      version: 2,
      name: "ROI New #{@token}",
      slug: "roi-new-#{@token.downcase}",
      renderer_key: "roi_calculator_v1",
      active: true,
      created_by: @definition_creator
    )

    get "/reports/tools/roi_calculator_#{@token}", headers: { "Accept" => "text/html" }

    assert_redirected_to "/reports/tools/roi_calculator_#{@token}/versions/2"
  end

  test "roi version route renders tool page" do
    Ec::ToolDefinition.create!(
      tool_type: "roi_calculator_#{@token}",
      version: 1,
      name: "ROI Calculator #{@token}",
      slug: "roi-show-definition-#{@token.downcase}",
      renderer_key: "roi_calculator_v1",
      active: true,
      created_by: @definition_creator
    )

    get "/reports/tools/roi_calculator_#{@token}/versions/1", headers: { "Accept" => "text/html", "Turbo-Frame" => "tool_drawer" }

    assert_response :success
    assert_select ".inventory-drawer.inventory-drawer--full.inventory-drawer--header-sm[data-close-path='/reports/tools'][style*='width: 90vw']"
    assert_select "[data-tool-type='roi_calculator_#{@token}'][data-tool-version='1'][data-tool-share-path='/reports/tools?tool_type=roi_calculator_#{@token}&version=1'].tool-renderer-page--full"
    assert_select ".roi-tool-inline"
    assert_select "#top-sku"
    assert_select "#btn-save", count: 0
    assert_select ".inventory-drawer__header button", text: "保存配置"
    assert_select "iframe", count: 0
    assert_includes response.body, "window.collectCurrentState = () => {"
    assert_includes response.body, "window.restoreState = (state = {}) => {"
    assert_includes response.body, "window.calculateAll = () => {"
  end

  test "renderer source serves the original roi calculator html" do
    get "/reports/tools/renderers/roi_calculator_v1/source", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_includes response.body, "SKU 成本与 ROI 智能测算台"
    assert_includes response.body, "const calculate = () => {"
  end

  test "smart pack version route renders tool page" do
    Ec::ToolDefinition.create!(
      tool_type: "smart_pack_calculator_#{@token}",
      version: 1,
      name: "SmartPack #{@token}",
      slug: "smart-pack-show-definition-#{@token.downcase}",
      renderer_key: "smart_pack_calculator_v1",
      active: true,
      created_by: @definition_creator
    )

    get "/reports/tools/smart_pack_calculator_#{@token}/versions/1", headers: { "Accept" => "text/html", "Turbo-Frame" => "tool_drawer" }

    assert_response :success
    assert_select ".inventory-drawer.inventory-drawer--full.inventory-drawer--header-sm[data-close-path='/reports/tools'][style*='width: 90vw']"
    assert_select "[data-tool-type='smart_pack_calculator_#{@token}'][data-tool-version='1'][data-tool-share-path='/reports/tools?tool_type=smart_pack_calculator_#{@token}&version=1'].tool-renderer-page--full"
    assert_select ".smart-pack-tool-inline"
    assert_select "#app-wrapper"
    assert_select "#len"
    assert_select "#box-canvas"
    assert_select "#pallet-canvas"
    assert_select ".inventory-drawer__header button", text: "保存配置"
    assert_select "iframe", count: 0
    assert_includes response.body, "window.collectCurrentState = () => {"
    assert_includes response.body, "window.restoreState = (state = {}) => {"
    assert_includes response.body, "window.calculateAll = () => {"
    assert_includes response.body, "window.executeDecisionEngine = executeDecisionEngine;"
  end

  test "renderer source serves the original smart pack calculator html" do
    get "/reports/tools/renderers/smart_pack_calculator_v1/source", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_includes response.body, "WB & Ozon 物流包装与装配规划系统"
    assert_includes response.body, "function executeDecisionEngine()"
  end

  test "index bootstraps the default wb pallet optimizer definition" do
    assert_difference -> { Ec::ToolDefinition.where(tool_type: "wb_pallet_optimizer").count }, 1 do
      assert_difference -> { Ec::ToolDefinition.where(tool_type: "roi_calculator").count }, 1 do
        assert_difference -> { Ec::ToolDefinition.where(tool_type: "smart_pack_calculator").count }, 1 do
          get "/reports/tools", headers: { "Accept" => "text/html" }
        end
      end
    end

    wb_definition = Ec::ToolDefinition.find_by!(tool_type: "wb_pallet_optimizer", version: 1)
    roi_definition = Ec::ToolDefinition.find_by!(tool_type: "roi_calculator", version: 1)
    smart_pack_definition = Ec::ToolDefinition.find_by!(tool_type: "smart_pack_calculator", version: 1)
    assert_equal "WB Pallet Optimizer", wb_definition.name
    assert_equal "ROI Calculator", roi_definition.name
    assert_equal "WB & Ozon SmartPack Calculator", smart_pack_definition.name
    assert_equal @current_user.id, wb_definition.created_by_id
    assert_equal @current_user.id, roi_definition.created_by_id
    assert_equal @current_user.id, smart_pack_definition.created_by_id
  end

  test "index does not duplicate bootstrapped definitions" do
    get "/reports/tools", headers: { "Accept" => "text/html" }

    assert_no_difference -> { Ec::ToolDefinition.where(tool_type: "wb_pallet_optimizer").count } do
      assert_no_difference -> { Ec::ToolDefinition.where(tool_type: "roi_calculator").count } do
        assert_no_difference -> { Ec::ToolDefinition.where(tool_type: "smart_pack_calculator").count } do
          get "/reports/tools", headers: { "Accept" => "text/html" }
        end
      end
    end
  end
end
