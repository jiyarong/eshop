module ErpAI
  class ConversationMessagesController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_permission!(:view_reports) }
    before_action :load_conversation

    def create
      @message = @conversation.messages.new(content: message_params[:content].to_s, role: "user")
      @message.images.attach(message_params[:images]) if message_params[:images].present?

      @conversation.with_lock do
        if @conversation.responding?
          @message.errors.add(:base, t("ai.conversations.errors.response_in_progress"))
          return render_invalid_message
        end

        @message.save!
        @conversation.update_response_status!("queued")
      end

      ConversationReplyJob.perform_later(@conversation.id, @message.id, locale: I18n.locale.to_s)

      render turbo_stream: [
        turbo_stream.append(
          "conversation_messages",
          partial: "erp_ai/conversations/message",
          locals: { message: @message }
        ),
        turbo_stream.replace(
          "conversation_composer",
          partial: "erp_ai/conversations/composer",
          locals: { conversation: @conversation, message: @conversation.messages.new, busy: true }
        )
      ], status: :accepted
    rescue ActiveRecord::RecordInvalid
      render_invalid_message
    rescue ActiveJob::EnqueueError
      @conversation.update_response_status!("failed")
      @message.errors.add(:base, t("ai.conversations.errors.enqueue_failed"))
      render_invalid_message
    end

    private

    def load_conversation
      @conversation = Conversation.find(params[:conversation_id])
    end

    def message_params
      params.require(:message).permit(:content, images: [])
    end

    def render_invalid_message
      @message.images.blobs.each(&:purge) unless @message.persisted?
      render turbo_stream: turbo_stream.replace(
        "conversation_composer",
        partial: "erp_ai/conversations/composer",
        locals: { conversation: @conversation, message: @message, busy: @conversation.responding? }
      ), status: :unprocessable_entity
    end
  end
end
