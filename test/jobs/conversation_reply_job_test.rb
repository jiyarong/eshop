require "test_helper"

class ConversationReplyJobTest < ActiveJob::TestCase
  class StreamingClient
    def complete(_request)
      yield '{"content":"后台' if block_given?
      yield '回复完成"}' if block_given?
      {
        content: "后台回复完成", tool_calls: [],
        usage: { "input_tokens" => 6, "output_tokens" => 2, "cached_tokens" => 4, "total_tokens" => 8 }
      }
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
    assert_equal({ "input_tokens" => 6, "output_tokens" => 2, "cached_tokens" => 4, "total_tokens" => 8 }, assistant.reload.usage)
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

  test "broadcasts the persisted token usage with the final streamed reply" do
    ErpAI::DefaultClient.default_client = StreamingClient.new
    replacements = []
    removals = []
    original_replace = Turbo::StreamsChannel.method(:broadcast_replace_to)
    original_remove = Turbo::StreamsChannel.method(:broadcast_remove_to)
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to) { |_conversation, **options| replacements << options }
    Turbo::StreamsChannel.define_singleton_method(:broadcast_remove_to) { |_conversation, **options| removals << options }

    ConversationReplyJob.perform_now(@conversation.id, @user_message.id, locale: "zh")

    reply = @conversation.messages.order(:created_at, :id).last
    broadcast = replacements.find { |options| options[:target] == "message_#{reply.id}" }
    assert broadcast
    assert_equal true, broadcast.fetch(:locals).fetch(:show_usage)
    assert removals.any? { |options| options[:target] == "conversation_token_usage" }

    markup = ApplicationController.render(partial: broadcast.fetch(:partial), locals: broadcast.fetch(:locals))
    fragment = Nokogiri::HTML.fragment(markup)
    assert_equal "8", fragment.at_css("#conversation_token_usage [data-token-metric='total_tokens'] .ai-conversation-message__usage-value").text
    assert_equal "4", fragment.at_css("#conversation_token_usage [data-token-metric='cached_tokens'] .ai-conversation-message__usage-value").text
  ensure
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to, original_replace) if original_replace
    Turbo::StreamsChannel.define_singleton_method(:broadcast_remove_to, original_remove) if original_remove
  end
end
