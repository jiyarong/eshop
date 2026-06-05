require "test_helper"

class Admin::AgentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @admin = create_user_with_roles("agent-admin-#{@token}@example.com", "super_admin")
    @viewer = create_user_with_roles("agent-viewer-#{@token}@example.com", "auditor")
    @agent = Agent.ensure_fixed!("sku_replenishment_advisor")
  end

  teardown do
    Message.where(conversation: Conversation.joins(:user).where(users: { email: [@admin.email, @viewer.email] })).delete_all if defined?(Message)
    Conversation.joins(:user).where(users: { email: [@admin.email, @viewer.email] }).delete_all if defined?(Conversation)
    UserRole.where(user: [@admin, @viewer]).delete_all
    User.where(id: [@admin.id, @viewer.id]).delete_all
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

  test "super admin can render edit form with fixed fields readonly" do
    sign_in @admin

    get "/admin/agents/sku_replenishment_advisor/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "编辑 AI Agent"
    assert_select "input[name='agent[model_id]'][value=?]", @agent.model_id
    assert_select "input[name='agent[temperature]'][value=?]", @agent.temperature.to_s
    assert_select "textarea[name='agent[system_prompt]']"
    assert_select "input[name='agent[name]']", false
    assert_select "input[name='agent[tools]']", false
    assert_select "input[name='agent[enabled]']", false
  end

  test "super admin can update tunable fields only" do
    sign_in @admin

    patch "/admin/agents/sku_replenishment_advisor", params: {
      agent: {
        name: "非法改名",
        enabled: "0",
        tools: ["router"],
        system_prompt: "自定义补货分析提示词",
        model_id: "deepseek-chat",
        temperature: "0.45"
      }
    }

    assert_redirected_to "/admin/agents"
    @agent.reload
    assert_equal "SKU 补货建议助手", @agent.name
    assert @agent.enabled?
    assert_equal ErpAI::ToolRegistry.default_tool_names, @agent.tools
    assert_equal "自定义补货分析提示词", @agent.system_prompt
    assert_equal "deepseek-chat", @agent.model_id
    assert_equal 0.45, @agent.temperature.to_f
  end

  test "super admin can update tunable fields with browser post fallback" do
    sign_in @admin

    post "/admin/agents/sku_replenishment_advisor", params: {
      agent: {
        system_prompt: "POST 表单提交提示词",
        model_id: "deepseek-chat",
        temperature: "0.35"
      }
    }

    assert_redirected_to "/admin/agents"
    @agent.reload
    assert_equal "POST 表单提交提示词", @agent.system_prompt
    assert_equal "deepseek-chat", @agent.model_id
    assert_equal 0.35, @agent.temperature.to_f
  end
end
