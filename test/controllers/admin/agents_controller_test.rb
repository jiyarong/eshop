require "test_helper"

class Admin::AgentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @admin = create_user_with_roles("agent-admin-#{@token}@example.com", "super_admin")
    @viewer = create_user_with_roles("agent-viewer-#{@token}@example.com", "auditor")
    @agent = Agent.ensure_fixed!("sku_replenishment_advisor")
    @agent.agent_skills.delete_all
    definition = Agent.definition_for!("sku_replenishment_advisor")
    @agent.update!(
      name: definition.fetch(:name),
      description: "",
      system_prompt: definition.fetch(:default_system_prompt),
      model_id: definition.fetch(:default_model_id),
      temperature: definition.fetch(:default_temperature),
      thinking_enabled: false,
      thinking_level: "",
      agent_type: :web,
      enabled: true,
      recommended_prompts: []
    )
    package = SkillPackage.from_markdown(skill_md)
    @skill = Skill.create!(
      name: package.name,
      description: package.description,
      version: "1",
      skill_md: package.skill_md
    )
    @skill.archive.attach(
      io: StringIO.new(package.archive_data),
      filename: "#{@skill.name}.zip",
      content_type: "application/zip"
    )
  end

  teardown do
    Message.where(conversation: Conversation.joins(:user).where(users: { email: [ @admin.email, @viewer.email ] })).delete_all if defined?(Message)
    Conversation.joins(:user).where(users: { email: [ @admin.email, @viewer.email ] }).delete_all if defined?(Conversation)
    AgentSkill.where(skill_id: @skill.id).delete_all
    Array(@filter_agents).each { |agent| Agent.find_by(id: agent.id)&.destroy! }
    Agent.where(code: "custom_agent_#{@token}").delete_all
    @agent.avatar.purge if @agent.avatar.attached?
    @skill.archive.purge if @skill.archive.attached?
    @skill.destroy!
    UserRole.where(user: [ @admin, @viewer ]).delete_all
    User.where(id: [ @admin.id, @viewer.id ]).delete_all
  end

  test "super admin can list fixed agents" do
    sign_in @admin

    get "/admin/agents", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "AI Agent 管理"
    assert_select ".ai-admin-tabs a[aria-current='page']", "AI Agent 管理"
    assert_select ".ai-agent-identity code", "sku_replenishment_advisor"
    assert_select ".ai-agent-identity strong", "SKU 补货建议助手"
    assert_select "th", text: "Agent 类型"
    assert_select ".ai-agent-table th", count: 6
    assert_select "th", text: I18n.t("admin.agents.fields.skills"), count: 0
    assert_select "td", text: "Web Agent"
    assert_select "a.ai-row-action[href=?]", "/admin/agents/sku_replenishment_advisor/edit"
    Agent::DEFINITIONS.each_key do |code|
      assert_select "form[action=?] input[name='agent_code'][value=?]", ai_conversations_path, code, count: 0
      assert_select "form[action=?] input[name='_method'][value='delete']", admin_agent_path(code), count: 0
    end
    nav_paths = css_select(".erp-nav__link").map { |link| link["href"] }
    assert_equal nav_paths.index(admin_agents_path) + 1, nav_paths.index(ai_conversations_path)
    assert_select ".ai-table-panel.table-list-card > .table-viewport.table-list-viewport[data-controller~='sticky-table-header'] > table.ai-agent-table",
      count: 1
  end

  test "agent list distinguishes built-in and custom agents by code" do
    create_filter_agents
    @filter_agents.first.update!(name: @agent.name)
    sign_in @admin

    get admin_agents_path, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".ai-agent-identity" do |identities|
      identities.each do |identity|
        origin = Agent::DEFINITIONS.key?(identity.at_css("code").text) ? "built_in" : "custom"
        assert_select identity, ".ai-agent-identity__name .ai-tag.ai-agent-origin--#{origin.dasherize}",
          text: I18n.t("admin.agents.origins.#{origin}"), count: 1
      end
    end
    assert_select ".ai-agent-identity strong", text: @agent.name, count: 2
  end

  test "agent list hides assigned skills without removing them" do
    @agent.update!(agent_type: :client, tools: [])
    @agent.skills << @skill
    sign_in @admin

    get admin_agents_path, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".ai-agent-identity code", @agent.code
    assert_select ".ai-agent-table td", text: @skill.name, count: 0
    assert_equal [ @skill.id ], @agent.skill_ids
  end

  test "agent list filters by either status" do
    create_filter_agents

    %w[enabled disabled].each do |status|
      sign_in @admin
      get admin_agents_path(status: status), headers: { "Accept" => "text/html" }

      assert_response :success
      displayed_codes = css_select(".ai-agent-identity code").map(&:text)
      expected_agents = @filter_agents.select { |agent| agent.enabled? == (status == "enabled") }
      assert_equal expected_agents.map(&:code).sort, (displayed_codes & @filter_agents.map(&:code)).sort
      assert_select ".ai-agent-table tbody tr td:nth-child(4)",
        text: I18n.t("admin.agents.statuses.#{status}"), count: displayed_codes.size
      assert_select "#agent-status-filter-label ~ a.is-active[aria-current='true']",
        text: I18n.t("admin.agents.statuses.#{status}"), count: 1
    end
  end

  test "agent list filters by either type" do
    create_filter_agents

    Agent.agent_types.keys.each do |agent_type|
      sign_in @admin
      get admin_agents_path(agent_type: agent_type), headers: { "Accept" => "text/html" }

      assert_response :success
      displayed_codes = css_select(".ai-agent-identity code").map(&:text)
      expected_agents = @filter_agents.select { |agent| agent.agent_type == agent_type }
      assert_equal expected_agents.map(&:code).sort, (displayed_codes & @filter_agents.map(&:code)).sort
      assert_select ".ai-agent-table tbody tr td:nth-child(2)",
        text: I18n.t("admin.agents.agent_types.#{agent_type}"), count: displayed_codes.size
      assert_select "#agent-type-filter-label ~ a.is-active[aria-current='true']",
        text: I18n.t("admin.agents.agent_types.#{agent_type}"), count: 1
    end
  end

  test "agent filter labels combine filters and clear each independently" do
    create_filter_agents
    sign_in @admin

    get admin_agents_path(status: "disabled", agent_type: "client"), headers: { "Accept" => "text/html" }

    assert_response :success
    displayed_codes = css_select(".ai-agent-identity code").map(&:text)
    expected_agent = @filter_agents.find { |agent| agent.client? && !agent.enabled? }
    assert_equal [ expected_agent.code ], displayed_codes & @filter_agents.map(&:code)
    assert_select ".ai-agent-filters select, .ai-agent-filters input[type='submit']", count: 0
    assert_select "#agent-status-filter-label ~ a[href=?]", admin_agents_path(status: "enabled", agent_type: "client")
    assert_select "#agent-type-filter-label ~ a[href=?]", admin_agents_path(status: "disabled", agent_type: "web")

    status_reset = css_select("#agent-status-filter-label ~ a").first["href"]
    type_reset = css_select("#agent-type-filter-label ~ a").first["href"]
    assert_equal admin_agents_path(agent_type: "client"), status_reset
    assert_equal admin_agents_path(status: "disabled"), type_reset

    sign_in @admin
    get status_reset, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select ".ai-agent-identity code", @filter_agents.find { |agent| agent.client? && agent.enabled? }.code
    assert_select "#agent-status-filter-label ~ a.is-active[aria-current='true']", I18n.t("admin.agents.filters.all_statuses")

    sign_in @admin
    get type_reset, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select ".ai-agent-identity code", @filter_agents.find { |agent| agent.web? && !agent.enabled? }.code
    assert_select "#agent-type-filter-label ~ a.is-active[aria-current='true']", I18n.t("admin.agents.filters.all_types")
  end

  test "agent list ignores unsupported filter values" do
    create_filter_agents
    sign_in @admin

    get admin_agents_path(status: "unknown", agent_type: "unknown"), headers: { "Accept" => "text/html" }

    assert_response :success
    @filter_agents.each do |agent|
      assert_select ".ai-agent-identity code", agent.code
    end
    assert_select "#agent-status-filter-label ~ a.is-active[aria-current='true']", I18n.t("admin.agents.filters.all_statuses")
    assert_select "#agent-type-filter-label ~ a.is-active[aria-current='true']", I18n.t("admin.agents.filters.all_types")
  end

  test "unavailable agents cannot start a conversation from the list" do
    @agent.update!(enabled: false)
    sign_in @admin

    get admin_agents_path, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='agent_code'][value='sku_replenishment_advisor']", count: 0
    assert_select "input[name='agent_code'][value='sku_diagnosis']", count: 0
    assert_select "input[name='agent_code'][value='sku_planner']", count: 0
  end

  test "non admin cannot manage agents" do
    sign_in @viewer

    get "/admin/agents", headers: { "Accept" => "text/html" }

    assert_response :forbidden
  end

  test "only enabled custom web agents have conversation actions and custom web agents have delete actions" do
    create_filter_agents
    sign_in @admin

    get admin_agents_path, headers: { "Accept" => "text/html" }

    assert_response :success
    @filter_agents.each do |agent|
      assert_select "form[action=?] input[name='agent_code'][value=?]",
        ai_conversations_path, agent.code, count: agent.web? && agent.enabled? ? 1 : 0
      assert_select "form[action=?] input[name='_method'][value='delete']",
        admin_agent_path(agent.code), count: agent.web? ? 1 : 0
      if agent.web?
        assert_select "form[action=?][data-turbo-confirm=?]", admin_agent_path(agent.code),
          I18n.t("admin.agents.actions.delete_confirm", name: agent.name)
      end
    end
  end

  test "super admin can delete enabled and disabled custom web agents and their conversations" do
    create_filter_agents
    sign_in @admin

    @filter_agents.select(&:web?).each do |agent|
      sign_in @admin
      conversation = agent.conversations.create!(user: @admin)
      message = conversation.messages.create!(role: "user", content: "Test deletion")

      delete admin_agent_path(agent.code)

      assert_redirected_to admin_agents_path
      assert_equal I18n.t("admin.agents.notices.deleted"), flash[:notice]
      assert_not Agent.exists?(agent.id)
      assert_not Conversation.exists?(conversation.id)
      assert_not Message.exists?(message.id)
    end
  end

  test "built-in and custom client agents cannot be deleted" do
    create_filter_agents
    sign_in @admin

    ([ @agent ] + @filter_agents.select(&:client?)).each do |agent|
      sign_in @admin
      assert_no_difference "Agent.count" do
        delete admin_agent_path(agent.code)
      end
      assert_response :not_found
      assert Agent.exists?(agent.id)
    end
  end

  test "non admin cannot delete a custom web agent" do
    create_filter_agents
    sign_in @viewer
    agent = @filter_agents.find(&:web?)

    assert_no_difference "Agent.count" do
      delete admin_agent_path(agent.code)
    end

    assert_response :forbidden
    assert Agent.exists?(agent.id)
  end

  test "super admin can render the complete edit form" do
    sign_in @admin

    get "/admin/agents/sku_replenishment_advisor/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "编辑 AI Agent"
    assert_select "input[name='agent[model_id]'][value=?]", @agent.model_id
    assert_select "input[name='agent[temperature]'][value=?]", @agent.temperature.to_s
    assert_select "input[name='agent[thinking_enabled]'][type='checkbox']"
    assert_select "select[name='agent[thinking_level]']"
    assert_select "#agent_thinking_level", count: 1
    assert_select "form[data-agent-form-thinking-profiles-value]"
    assert_select "textarea[name='agent[system_prompt]']"
    assert_select "input[name='agent[name]'][value=?]", @agent.name
    assert_select "input[name='agent[agent_type]'][type='radio'][value='web'][checked]"
    assert_select "input[name='agent[agent_type]'][type='radio'][value='client']"
    assert_select "form[data-controller='agent-form']"
    assert_select "section[data-agent-form-target='toolPanel']"
    assert_select "input[data-agent-form-target='toolInput'][name='agent[tools][]']",
      count: ErpAI::ToolRegistry.default_tools.size - 1 + 6
    assert_select "input[data-agent-form-target='toolInput'][value='erp_ai_request']"
    assert_select "input#agent_tools_get_sku_context:not([checked])"
    %w[query search get_page list_pages traverse_graph think].each do |name|
      assert_select "input#agent_tools_gbrain__#{name}[name='agent[tools][]']:not([checked]):not([disabled])"
    end
    assert_select "strong", text: "SKU 上下文"
    assert_select "input#agent_tools_search__web_search[disabled]:not([checked])"
    assert_select "section[data-agent-form-target='skillPanel']"
    assert_select "input[data-agent-form-target='skillInput'][value=?]", @skill.id.to_s
    assert_select "textarea[name='agent[recommended_prompts_text]']"
    assert_select "input[name='agent[skill_ids][]'][value=?]", @skill.id.to_s
    assert_select "input[name='agent[avatar]'][type='file']"
    assert_select "input[name='agent[enabled]'][type='checkbox']"
    assert_select ".ai-editor-layout"
    assert_select ".ai-form-actions button[type='submit']"
  end

  test "super admin can see the configured Tavily web search tool" do
    sign_in @admin
    tavily_client = ErpAI::Mcp::TavilyClient.new(name: "search", api_keys: [ "test-key" ])
    registry = Struct.new(:clients, :tool_filters).new(
      { "search" => tavily_client },
      { "search" => [ "web_search" ] }
    )

    original_registry_new = ErpAI::Mcp::ServerRegistry.method(:new)
    ErpAI::Mcp::ServerRegistry.define_singleton_method(:new) { registry }
    begin
      get "/admin/agents/sku_replenishment_advisor/edit", headers: { "Accept" => "text/html" }
    ensure
      ErpAI::Mcp::ServerRegistry.define_singleton_method(:new, original_registry_new)
    end

    assert_response :success
    assert_select "input#agent_tools_search__web_search[disabled][checked]"
    assert_select "input#agent_tools_search__web_search[name='agent[tools][]']", count: 0
    assert_select "strong", text: "网页搜索"
  end

  test "super admin can render a new agent form" do
    sign_in @admin

    get new_admin_agent_path, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "新增 AI Agent"
    assert_select "input[name='agent[code]']"
    assert_select "input[name='agent[agent_type]'][type='radio'][value='web'][checked]"
    assert_select "input[data-agent-form-target='toolInput'][name='agent[tools][]']",
      count: ErpAI::ToolRegistry.default_tools.size - 1 + 6
    assert_select "input#agent_tools_search__web_search[disabled]"
    assert_select "input[name='agent[skill_ids][]'][value=?]", @skill.id.to_s
  end

  test "super admin can select and clear individual GBrain tools" do
    sign_in @admin

    patch admin_agent_path(@agent.code), params: {
      agent: { tools: [ "get_sku_context", "gbrain__query", "gbrain__search" ] }
    }

    assert_redirected_to admin_agents_path
    assert_equal %w[get_sku_context gbrain__query gbrain__search], @agent.reload.tools

    get edit_admin_agent_path(@agent.code), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input#agent_tools_gbrain__query[checked]:not([disabled])"
    assert_select "input#agent_tools_gbrain__search[checked]:not([disabled])"
    assert_select "input#agent_tools_gbrain__think:not([checked]):not([disabled])"

    patch admin_agent_path(@agent.code), params: { agent: { tools: [ "" ] } }

    assert_redirected_to admin_agents_path
    assert_empty @agent.reload.tools
  end

  test "super admin can update agent profile prompts and skills" do
    sign_in @admin

    patch "/admin/agents/sku_replenishment_advisor", params: {
      agent: {
        name: "自定义补货助手",
        description: "补货分析说明",
        enabled: "1",
        tools: [ "router" ],
        system_prompt: "自定义补货分析提示词",
        model_id: "deepseek-chat",
        temperature: "0.45",
        agent_type: "client",
        thinking_enabled: "1",
        thinking_level: "",
        recommended_prompts_text: "问题一\n\n问题二",
        skill_ids: [ @skill.id ]
      }
    }

    assert_redirected_to "/admin/agents"
    @agent.reload
    assert_equal "自定义补货助手", @agent.name
    assert_equal "补货分析说明", @agent.description
    assert @agent.enabled?
    assert_empty @agent.tools
    assert_equal "自定义补货分析提示词", @agent.system_prompt
    assert_equal "deepseek-chat", @agent.model_id
    assert_equal 0.45, @agent.temperature.to_f
    assert @agent.client?
    assert @agent.thinking_enabled?
    assert_equal [ "问题一", "问题二" ], @agent.recommended_prompts
    assert_equal [ @skill ], @agent.skills.to_a
  end

  test "saves supported GPT and DeepSeek thinking levels" do
    { "deepseek-v4-flash" => "max", "gpt-5.2" => "xhigh", "gpt-5" => "minimal" }.each do |model, level|
      sign_in @admin
      patch admin_agent_path(@agent.code), params: {
        agent: { model_id: model, thinking_enabled: "1", thinking_level: level }
      }

      assert_redirected_to admin_agents_path
      assert_equal model, @agent.reload.model_id
      assert_equal level, @agent.thinking_level
      assert @agent.thinking_enabled?
    end
  end

  test "multipart form saves the selected thinking level and restores it on the edit page" do
    sign_in @admin
    boundary = "agent-thinking-#{@token}"
    fields = [
      [ "agent[model_id]", "gpt-6-sol" ],
      [ "agent[thinking_enabled]", "1" ],
      [ "agent[thinking_level]", "" ],
      [ "agent[thinking_level]", "high" ]
    ]
    body = fields.map do |name, value|
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
    end.join + "--#{boundary}--\r\n"

    patch admin_agent_path(@agent.code), params: body,
      headers: { "CONTENT_TYPE" => "multipart/form-data; boundary=#{boundary}", "Accept" => "text/html" }

    assert_redirected_to admin_agents_path
    assert_equal "high", @agent.reload.thinking_level
    Agent.seed_fixed!
    assert_equal "high", @agent.reload.thinking_level

    sign_in @admin
    get edit_admin_agent_path(@agent.code), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "select[name='agent[thinking_level]'] option[value='high'][selected]"
    assert_select "input[type='hidden'][name='agent[thinking_level]'][value='high']"
  end

  test "rejects thinking levels unsupported by the selected model" do
    sign_in @admin

    patch admin_agent_path(@agent.code), params: {
      agent: { model_id: "deepseek-v4-flash", thinking_enabled: "1", thinking_level: "xhigh" }
    }

    assert_response :unprocessable_entity
    assert_equal "", @agent.reload.thinking_level
  end

  test "keeps configured thinking level when thinking is disabled" do
    sign_in @admin
    @agent.update!(model_id: "deepseek-v4-flash", thinking_enabled: true, thinking_level: "max")

    patch admin_agent_path(@agent.code), params: { agent: { thinking_enabled: "0", thinking_level: "max" } }

    assert_redirected_to admin_agents_path
    assert_not @agent.reload.thinking_enabled?
    assert_equal "max", @agent.thinking_level
  end

  test "saved SKU Planner prompt remains in the database after the admin page seeds agents" do
    planner_existed = Agent.exists?(code: "sku_planner")
    planner = Agent.ensure_fixed!("sku_planner")
    original_prompt = planner.system_prompt
    sign_in @admin

    patch "/admin/agents/sku_planner", params: { agent: { system_prompt: "后台保存的 Planner 提示词" } }
    assert_redirected_to "/admin/agents"
    Agent.seed_fixed!

    assert_equal "后台保存的 Planner 提示词", planner.reload.system_prompt
  ensure
    if planner&.persisted?
      planner_existed ? planner.update_columns(system_prompt: original_prompt) : Agent.where(id: planner.id).delete_all
    end
  end

  test "super admin can configure tools for a web agent" do
    sign_in @admin

    patch "/admin/agents/sku_replenishment_advisor", params: {
      agent: {
        agent_type: "web",
        tools: [ "erp_ai_request", "query_inventory_data" ],
        skill_ids: [ @skill.id ]
      }
    }

    assert_redirected_to "/admin/agents"
    @agent.reload
    assert @agent.web?
    assert_equal [ "erp_ai_request", "query_inventory_data" ], @agent.tools
    assert_empty @agent.skills
  end

  test "super admin can upload an agent avatar" do
    sign_in @admin
    avatar = Tempfile.new([ "agent-avatar", ".png" ])
    avatar.binmode
    avatar.write("\x89PNG\r\n\x1A\n")
    avatar.rewind

    patch "/admin/agents/sku_replenishment_advisor", params: {
      agent: {
        avatar: Rack::Test::UploadedFile.new(
          avatar.path,
          "image/png",
          true,
          original_filename: "agent-avatar.png"
        )
      }
    }

    assert_redirected_to "/admin/agents"
    assert @agent.reload.avatar.attached?
    assert_equal "agent-avatar.png", @agent.avatar.filename.to_s
    assert_equal "image/png", @agent.avatar.content_type
  ensure
    avatar&.close!
  end

  test "super admin can create a custom agent" do
    sign_in @admin
    custom_code = "custom_agent_#{@token}"

    assert_difference -> { Agent.where(code: custom_code).count }, 1 do
      post "/admin/agents", params: {
        agent: {
          code: custom_code,
          name: "自定义 Agent",
          description: "自定义说明",
          enabled: "1",
          system_prompt: "自定义系统提示词",
          model_id: "deepseek-v4-flash",
          temperature: "0.3",
          agent_type: "client",
          thinking_enabled: "0",
          recommended_prompts_text: "如何开始？",
          skill_ids: [ @skill.id ]
        }
      }
    end

    assert_redirected_to "/admin/agents"
    agent = Agent.find_by!(code: custom_code)
    assert agent.client?
    assert_empty agent.tools
    assert_equal [ "如何开始？" ], agent.recommended_prompts
    assert_equal [ @skill ], agent.skills.to_a
  end

  test "web agents cannot keep skills" do
    sign_in @admin
    @agent.update!(agent_type: :client, tools: [])
    @agent.skills << @skill

    patch "/admin/agents/sku_replenishment_advisor", params: {
      agent: {
        agent_type: "web",
        skill_ids: [ @skill.id ]
      }
    }

    assert_redirected_to "/admin/agents"
    assert @agent.reload.web?
    assert_empty @agent.skills

    agent_skill = AgentSkill.new(agent: @agent, skill: @skill)
    assert_not agent_skill.valid?
  end

  test "client agents cannot keep tools" do
    sign_in @admin

    patch "/admin/agents/sku_replenishment_advisor", params: {
      agent: {
        agent_type: "client",
        tools: [ "query_inventory_data" ],
        skill_ids: [ @skill.id ]
      }
    }

    assert_redirected_to "/admin/agents"
    @agent.reload
    assert @agent.client?
    assert_empty @agent.tools
    assert_equal [ @skill ], @agent.skills.to_a
  end

  test "super admin can update tunable fields with browser post fallback" do
    sign_in @admin

    post "/admin/agents/sku_replenishment_advisor", params: {
      agent: {
        system_prompt: "POST 表单提交提示词",
        model_id: "deepseek-chat",
        temperature: "0.35",
        thinking_enabled: "0"
      }
    }

    assert_redirected_to "/admin/agents"
    @agent.reload
    assert_equal "POST 表单提交提示词", @agent.system_prompt
    assert_equal "deepseek-chat", @agent.model_id
    assert_equal 0.35, @agent.temperature.to_f
    assert_not @agent.thinking_enabled?
  end


  private

  def create_filter_agents
    @filter_agents = []
    Agent.agent_types.keys.each do |agent_type|
      [ true, false ].each do |enabled|
        @filter_agents << Agent.create!(
          code: "filter_#{agent_type}_#{enabled}_#{@token}",
          name: "Filter #{agent_type} #{enabled}",
          agent_type: agent_type,
          enabled: enabled,
          system_prompt: "Filter test prompt",
          model_id: "deepseek-chat",
          temperature: 0.3,
          tools: []
        )
      end
    end
  end

  def skill_md
    <<~MARKDOWN
      ---
      name: agent-skill-#{@token}
      description: Agent test skill
      ---

      # Workflow

      Follow the workflow.
    MARKDOWN
  end
end
