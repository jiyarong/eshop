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

  test "creates general agent conversation with only question" do
    sign_in @user

    post "/ai/conversations.json", params: {
      agent_code: "general_agent",
      question: "帮我总结外部资料"
    }

    assert_response :created
    body = JSON.parse(response.body)
    assert_nil body.fetch("conversation").fetch("module_name")
    assert_match "库存数据不足", body.fetch("assistant_message").fetch("content")
  end

  test "renders the conversation as markdown and includes tool results" do
    sign_in @user
    conversation = @agent.conversations.create!(user: @user, module_name: "inventory")
    conversation.messages.create!(role: "user", content: "分析 SKU-1")
    conversation.messages.create!(
      role: "assistant",
      content: { tool_calls: [ { "name" => "query_inventory_data", "arguments" => { "sku" => "SKU-1" } } ] }.to_json
    )
    conversation.messages.create!(
      role: "tool",
      content: { "tool_name" => "query_inventory_data", "content" => [ { "type" => "text", "text" => "库存 3 件" } ] }.to_json
    )
    conversation.messages.create!(role: "assistant", content: "## 结论\n\n库存需要补充确认。")

    get "/ai/conversations/#{conversation.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".ai-conversation-message", count: 4
    assert_select ".ai-conversation-message--assistant .ai-conversation-message__source", text: /query_inventory_data/
    assert_select ".ai-conversation-message--tool", text: /工具调用结果/
    assert_select ".ai-conversation-message--tool", text: /库存 3 件/
    assert_select "article[data-markdown-target='output'][hidden]", count: 4
  end

  test "does not expose another user's unlinked conversation" do
    other_user = create_user_with_roles("ai-controller-other-#{@token}@example.com", "manager")
    conversation = @agent.conversations.create!(user: other_user)
    conversation.messages.create!(role: "user", content: "私有请求")
    sign_in @user

    get "/ai/conversations/#{conversation.id}", headers: { "Accept" => "text/html" }

    assert_response :not_found
  ensure
    Message.where(conversation: Conversation.where(user: other_user)).delete_all if other_user
    Conversation.where(user: other_user).delete_all if other_user
    UserRole.where(user: other_user).delete_all if other_user
    User.where(id: other_user&.id).delete_all if other_user
  end
end
