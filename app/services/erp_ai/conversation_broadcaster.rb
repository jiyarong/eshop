module ErpAI
  class ConversationBroadcaster
    include ActionView::RecordIdentifier

    def initialize(conversation)
      @conversation = conversation
    end

    def append_message(message)
      Turbo::StreamsChannel.broadcast_append_to(
        conversation,
        target: "conversation_messages",
        partial: "erp_ai/conversations/message",
        locals: message_locals(message)
      )
    end

    def replace_message(message)
      Turbo::StreamsChannel.broadcast_replace_to(
        conversation,
        target: dom_id(message),
        partial: "erp_ai/conversations/message",
        locals: message_locals(message)
      )
    end

    def stream_message(message, content)
      return if content.blank?

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if @last_stream_broadcast_at && now - @last_stream_broadcast_at < 0.05

      @last_stream_broadcast_at = now
      Turbo::StreamsChannel.broadcast_replace_to(
        conversation,
        target: "#{dom_id(message)}_body",
        partial: "erp_ai/conversations/message_body",
        locals: { message: message, content: content, streaming: true }
      )
    end

    def replace_composer
      Turbo::StreamsChannel.broadcast_replace_to(
        conversation,
        target: "conversation_composer",
        partial: "erp_ai/conversations/composer",
        locals: {
          conversation: conversation,
          message: Message.new(conversation: conversation),
          busy: conversation.responding?
        }
      )
    end

    private

    attr_reader :conversation

    def message_locals(message)
      time_zone = User.profile_time_zone(conversation.user.time_zone)
      {
        message: message,
        displayed_at: message.created_at.in_time_zone(time_zone).strftime("%Y-%m-%d %H:%M")
      }
    end
  end
end
