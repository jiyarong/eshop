require "test_helper"

class ErpAI::ConversationsControllerTest < ActionDispatch::IntegrationTest
  class FakeClient
    def complete(_request)
      {
        content: "## 结论摘要\n库存数据不足，需要补充确认。",
        usage: { "total_tokens" => 12 }
      }
    end
  end

  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("ai-controller-#{@token}@example.com", "manager")
    @agent = Agent.ensure_fixed!("business_analysis")
    @old_default_client = ErpAI::DefaultClient.default_client
    ErpAI::DefaultClient.default_client = FakeClient.new
  end

  teardown do
    ErpAI::DefaultClient.default_client = @old_default_client
    Message.where(conversation: Conversation.where(user: @user)).delete_all if defined?(Message)
    Conversation.where(user: @user).delete_all if defined?(Conversation)
    Agent.where(id: @agent.id).delete_all if defined?(Agent) && @agent&.id
    UserRole.where(user: @user).delete_all
    User.where(id: @user.id).delete_all
  end

  test "requires login" do
    post "/ai/conversations.json", params: { question: "分析库存" }

    assert_response :unauthorized
  end

  test "creates conversation with ERP context" do
    sign_in @user

    post "/ai/conversations.json", params: {
      agent_code: "business_analysis",
      question: "请分析库存风险",
      module_name: "inventory",
      business_object_type: "Ec::Sku",
      business_object_id: "SKU-1",
      time_range: { from: "2026-05-01", to: "2026-05-31" },
      data_summary: "库存 3 件，近 7 日销量 20 件。"
    }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "inventory", body.fetch("conversation").fetch("module_name")
    assert_match "库存数据不足", body.fetch("assistant_message").fetch("content")
    assert_equal({ "total_tokens" => 12 }, body.fetch("assistant_message").fetch("usage"))
  end
end
