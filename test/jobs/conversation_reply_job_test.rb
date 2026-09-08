require "test_helper"

class ConversationReplyJobTest < ActiveJob::TestCase
  class StreamingClient
    def complete(_request)
      yield '{"content":"后台' if block_given?
      yield '回复完成"}' if block_given?
      { content: "后台回复完成", tool_calls: [], usage: { "total_tokens" => 8 } }
    end
  end

  class FailingClient
    def complete(_request)
      raise "provider unavailable"
    end
  end

  setup do
    @token = SecureRandom.hex(4)
    @user = User.create!(
      email: "conversation-job-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @agent = Agent.ensure_fixed!("business_analysis")
    @conversation = @agent.conversations.create!(user: @user)
    @user_message = @conversation.messages.create!(role: "user", content: "继续分析")
    @conversation.update_response_status!("queued")
    @old_default_client = ErpAI::DefaultClient.default_client
  end

  teardown do
    ErpAI::DefaultClient.default_client = @old_default_client
    Message.where(conversation: @conversation).delete_all
    Conversation.where(id: @conversation.id).delete_all
    Agent.where(id: @agent.id).delete_all
    User.where(id: @user.id).delete_all
  end

  test "streams and persists a reply before marking the conversation idle" do
    ErpAI::DefaultClient.default_client = StreamingClient.new

    ConversationReplyJob.perform_now(@conversation.id, @user_message.id, locale: "zh")

    assert_equal "idle", @conversation.reload.response_status
    assistant = @conversation.messages.order(:created_at, :id).last
    assert_equal "assistant", assistant.role
    assert_equal "后台回复完成", assistant.content
    assert_equal({ "total_tokens" => 8 }, assistant.usage)
  end

  test "marks the conversation failed and leaves a visible error message" do
    ErpAI::DefaultClient.default_client = FailingClient.new

    assert_raises RuntimeError do
      ConversationReplyJob.perform_now(@conversation.id, @user_message.id, locale: "zh")
    end

    assert_equal "failed", @conversation.reload.response_status
    assert_equal I18n.t("ai.conversations.errors.response_failed", locale: :zh),
                 @conversation.messages.order(:created_at, :id).last.content
  end
end
