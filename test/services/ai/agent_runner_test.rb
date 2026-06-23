require "test_helper"

class ErpAI::AgentRunnerTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :request

    def complete(request)
      @request = request
      {
        content: "## 结论摘要\n库存存在缺口，需要补充确认近期销量。",
        usage: { "total_tokens" => 42 }
      }
    end
  end

  setup do
    @token = SecureRandom.hex(4)
    @user = User.create!(
      email: "ai-runner-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @agent = Agent.ensure_fixed!("business_analysis")
    @agent.update!(model_id: "fake-model", temperature: 0.3)
  end

  teardown do
    Message.where(conversation: Conversation.where(user: @user)).delete_all if defined?(Message)
    Conversation.where(user: @user).delete_all if defined?(Conversation)
    Agent.where(id: @agent.id).delete_all if defined?(Agent) && @agent&.id
    User.where(email: @user.email).delete_all
  end

  test "creates a conversation and persists user and assistant messages" do
    client = FakeClient.new

    conversation = ErpAI::AgentRunner.new(
      agent: @agent,
      user: @user,
      client: client
    ).ask(
      question: "请给出库存建议",
      module_name: "inventory",
      business_object_type: "Ec::Sku",
      business_object_id: "SKU-1",
      time_range: { "from" => "2026-05-01", "to" => "2026-05-31" },
      data_summary: "SKU-1 当前库存 3 件，近 7 日销量 20 件。"
    )

    assert_equal "inventory", conversation.module_name
    assert_equal ["user", "assistant"], conversation.messages.order(:created_at, :id).pluck(:role)
    assert_equal "请给出库存建议", conversation.messages.order(:created_at, :id).first.content
    assert_match "库存存在缺口", conversation.messages.order(:created_at, :id).last.content
    assert_equal({ "total_tokens" => 42 }, conversation.messages.order(:created_at, :id).last.usage)
  end

  test "injects ERP context and query-only tools into LLM request" do
    client = FakeClient.new

    I18n.with_locale(:ru) do
      ErpAI::AgentRunner.new(agent: @agent, user: @user, client: client).ask(
        question: "分析库存异常",
        module_name: "inventory",
        time_range: { "from" => "2026-05-01", "to" => "2026-05-31" },
        data_summary: "库存数据摘要"
      )
    end

    request = client.request
    assert_equal "fake-model", request.fetch(:model)
    assert_equal 0.3, request.fetch(:temperature)
    assert_includes request.fetch(:system_prompt), "嵌入 ERP 系统的业务分析 AI Agent"
    assert_includes request.fetch(:context), "当前用户界面语言：ru"
    assert_includes request.fetch(:context), "当前 ERP 模块：inventory"
    assert_includes request.fetch(:context), "当前用户角色和权限范围"
    assert_includes request.fetch(:context), "库存数据摘要"
    assert_includes request.fetch(:tools).map { |tool| tool.fetch(:name) }, "query_inventory_data"
    assert_not_includes request.fetch(:tools).map { |tool| tool.fetch(:name) }, "router"
    assert_not_includes request.fetch(:tools).map { |tool| tool.fetch(:name) }, "export_pdf"
  end
end
