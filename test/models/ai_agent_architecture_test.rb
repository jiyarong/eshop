require "test_helper"

class AiAgentArchitectureTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4)
    @user = User.create!(
      email: "ai-agent-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  teardown do
    Message.where(conversation: Conversation.where(user: @user)).delete_all if defined?(Message)
    Conversation.where(user: @user).delete_all if defined?(Conversation)
    Agent.where(code: Agent::DEFINITIONS.keys + ["custom_dynamic_agent"]).delete_all if defined?(Agent)
    User.where(email: @user.email).delete_all
  end

  test "fixed agent stores only ERP query tools" do
    agent = Agent.ensure_fixed!("business_analysis")

    assert_equal "business_analysis", agent.code
    assert_equal "经营分析助手", agent.name
    assert agent.enabled?
    assert_includes agent.tools, "query_inventory_data"
    assert_not_includes agent.tools, "router"
    assert_not_includes agent.tools, "export_pdf"
    assert_not_includes agent.tools, "export_word"
  end

  test "fixed definitions include scenario-specific agents" do
    assert_equal [
      "business_analysis",
      "sku_replenishment_advisor",
      "sku_weekly_report_advisor",
      "page_translation",
      "general_agent"
    ], Agent::DEFINITIONS.keys

    assert_equal "SKU 补货建议助手", Agent::DEFINITIONS.fetch("sku_replenishment_advisor").fetch(:name)
    assert_equal "SKU 周报提醒助手", Agent::DEFINITIONS.fetch("sku_weekly_report_advisor").fetch(:name)
    assert_equal "页面翻译助手", Agent::DEFINITIONS.fetch("page_translation").fetch(:name)
    assert_equal "通用助手", Agent::DEFINITIONS.fetch("general_agent").fetch(:name)
    assert_includes Agent::DEFINITIONS.fetch("sku_replenishment_advisor").fetch(:default_system_prompt), "补货建议"
    assert_includes Agent::DEFINITIONS.fetch("sku_weekly_report_advisor").fetch(:default_system_prompt), "SKU 周报"
    assert_includes Agent::DEFINITIONS.fetch("page_translation").fetch(:default_system_prompt), "翻译"
    assert_includes Agent::DEFINITIONS.fetch("page_translation").fetch(:default_system_prompt), "保持 HTML"
    assert_includes Agent::DEFINITIONS.fetch("page_translation").fetch(:default_system_prompt), "JSON"
    assert_includes Agent::DEFINITIONS.fetch("page_translation").fetch(:default_system_prompt), "省略"
    assert_includes Agent::DEFINITIONS.fetch("general_agent").fetch(:default_system_prompt), "通用 AI Agent"
    assert_equal [], Agent::DEFINITIONS.fetch("general_agent").fetch(:tools)
  end

  test "seeds all fixed agents without overwriting tunable fields" do
    tuned_agent = Agent.ensure_fixed!("sku_replenishment_advisor")
    tuned_agent.update!(
      system_prompt: "自定义补货提示词",
      model_id: "custom-model",
      temperature: 0.45
    )

    Agent.seed_fixed!

    assert_equal Agent::DEFINITIONS.keys.sort, Agent.order(:code).pluck(:code).sort
    tuned_agent.reload
    assert_equal "自定义补货提示词", tuned_agent.system_prompt
    assert_equal "custom-model", tuned_agent.model_id
    assert_equal 0.45, tuned_agent.temperature.to_f
  end

  test "custom agents are allowed" do
    agent = Agent.new(
      code: "custom_dynamic_agent",
      name: "临时 Agent",
      system_prompt: Agent::DEFAULT_SYSTEM_PROMPT,
      model_id: "fake-model",
      temperature: 0.3,
      tools: ErpAI::ToolRegistry.default_tool_names,
      enabled: true
    )

    assert agent.valid?
  end

  test "fixed agent profile fields remain customized when definitions are seeded" do
    agent = Agent.ensure_fixed!("business_analysis")

    agent.name = "可修改名称"
    agent.enabled = false
    agent.save!
    Agent.seed_fixed!

    assert_equal "可修改名称", agent.reload.name
    assert_not agent.enabled?
  end

  test "fixed agent allows prompt model and temperature tuning" do
    agent = Agent.ensure_fixed!("business_analysis")

    agent.update!(
      system_prompt: "#{Agent::DEFAULT_SYSTEM_PROMPT}\n请优先输出三条建议。",
      model_id: "deepseek-chat",
      temperature: 0.4
    )

    assert_equal "deepseek-chat", agent.model_id
    assert_equal 0.4, agent.temperature.to_f
    assert_includes agent.system_prompt, "三条建议"
  end

  test "conversation stores ERP context and ordered messages" do
    agent = Agent.ensure_fixed!("business_analysis")
    conversation = Conversation.create!(
      agent: agent,
      user: @user,
      module_name: "inventory",
      business_object_type: "Ec::Sku",
      business_object_id: "SKU-1",
      time_range: { "from" => "2026-05-01", "to" => "2026-05-31" }
    )

    conversation.messages.create!(role: "user", content: "分析库存风险")
    conversation.messages.create!(role: "assistant", content: "库存风险摘要")

    assert_equal @user, conversation.user
    assert_equal "inventory", conversation.module_name
    assert_equal({ "from" => "2026-05-01", "to" => "2026-05-31" }, conversation.time_range)
    assert_equal ["user", "assistant"], conversation.messages.order(:created_at, :id).pluck(:role)
  end
end
