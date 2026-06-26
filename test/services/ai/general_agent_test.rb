require "test_helper"

class ErpAI::GeneralAgentTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :request

    def complete(request)
      @request = request
      {
        content: "通用回答",
        tool_calls: [],
        usage: { "total_tokens" => 8 }
      }
    end
  end

  setup do
    @token = SecureRandom.hex(4)
    @user = User.create!(
      email: "general-agent-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  teardown do
    Message.where(conversation: Conversation.where(user: @user)).delete_all if defined?(Message)
    Conversation.where(user: @user).delete_all if defined?(Conversation)
    Agent.where(code: "general_agent").delete_all if defined?(Agent)
    User.where(email: @user.email).delete_all
  end

  test "asks general agent with only question and uses agent loop" do
    client = FakeClient.new

    conversation = ErpAI::GeneralAgent.new(user: @user, client: client).ask("帮我查一下资料")

    assert_equal "general_agent", conversation.agent.code
    assert_nil conversation.module_name
    assert_equal ["user", "assistant"], conversation.messages.order(:created_at, :id).pluck(:role)
    assert_equal "帮我查一下资料", conversation.messages.order(:created_at, :id).first.content
    assert_equal "通用回答", conversation.messages.order(:created_at, :id).last.content
    assert_includes client.request.fetch(:system_prompt), "通用 AI Agent"
  end
end
