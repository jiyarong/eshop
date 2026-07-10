require "test_helper"

class Admin::AgentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @admin = create_user_with_roles("agent-admin-#{@token}@example.com", "super_admin")
    @viewer = create_user_with_roles("agent-viewer-#{@token}@example.com", "auditor")
    @agent = Agent.ensure_fixed!("sku_replenishment_advisor")
    definition = Agent.definition_for!("sku_replenishment_advisor")
    @agent.update!(
      name: definition.fetch(:name),
      description: "",
      system_prompt: definition.fetch(:default_system_prompt),
      model_id: definition.fetch(:default_model_id),
      temperature: definition.fetch(:default_temperature),
      thinking_enabled: false,
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
    Agent.where(code: "custom_agent_#{@token}").delete_all
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
    assert_select "td", "sku_replenishment_advisor"
    assert_select "td", "SKU 补货建议助手"
    assert_select "a[href=?]", "/admin/agents/sku_replenishment_advisor/edit", "编辑"
  end

  test "non admin cannot manage agents" do
    sign_in @viewer

    get "/admin/agents", headers: { "Accept" => "text/html" }

    assert_response :forbidden
  end

  test "super admin can render the complete edit form" do
    sign_in @admin

    get "/admin/agents/sku_replenishment_advisor/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "编辑 AI Agent"
    assert_select "input[name='agent[model_id]'][value=?]", @agent.model_id
    assert_select "input[name='agent[temperature]'][value=?]", @agent.temperature.to_s
    assert_select "input[name='agent[thinking_enabled]'][type='checkbox']"
    assert_select "textarea[name='agent[system_prompt]']"
    assert_select "input[name='agent[name]'][value=?]", @agent.name
    assert_select "textarea[name='agent[recommended_prompts_text]']"
    assert_select "input[name='agent[skill_ids][]'][value=?]", @skill.id.to_s
    assert_select "input[name='agent[avatar]'][type='file']"
    assert_select "input[name='agent[tools]']", false
    assert_select "input[name='agent[enabled]'][type='checkbox']"
  end

  test "super admin can render a new agent form" do
    sign_in @admin

    get new_admin_agent_path, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "新增 AI Agent"
    assert_select "input[name='agent[code]']"
    assert_select "input[name='agent[skill_ids][]'][value=?]", @skill.id.to_s
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
        thinking_enabled: "1",
        recommended_prompts_text: "问题一\n\n问题二",
        skill_ids: [ @skill.id ]
      }
    }

    assert_redirected_to "/admin/agents"
    @agent.reload
    assert_equal "自定义补货助手", @agent.name
    assert_equal "补货分析说明", @agent.description
    assert @agent.enabled?
    assert_equal ErpAI::ToolRegistry.default_tool_names, @agent.tools
    assert_equal "自定义补货分析提示词", @agent.system_prompt
    assert_equal "deepseek-chat", @agent.model_id
    assert_equal 0.45, @agent.temperature.to_f
    assert @agent.thinking_enabled?
    assert_equal [ "问题一", "问题二" ], @agent.recommended_prompts
    assert_equal [ @skill ], @agent.skills.to_a
  end

  test "super admin can create a custom agent" do
    sign_in @admin

    assert_difference "Agent.count", 1 do
      post "/admin/agents", params: {
        agent: {
          code: "custom_agent_#{@token}",
          name: "自定义 Agent",
          description: "自定义说明",
          enabled: "1",
          system_prompt: "自定义系统提示词",
          model_id: "deepseek-v4-flash",
          temperature: "0.3",
          thinking_enabled: "0",
          recommended_prompts_text: "如何开始？",
          skill_ids: [ @skill.id ]
        }
      }
    end

    assert_redirected_to "/admin/agents"
    agent = Agent.find_by!(code: "custom_agent_#{@token}")
    assert_equal [ "如何开始？" ], agent.recommended_prompts
    assert_equal [ @skill ], agent.skills.to_a
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
