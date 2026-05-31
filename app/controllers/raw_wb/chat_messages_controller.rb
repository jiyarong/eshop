module RawWb
  class ChatMessagesController < BaseController
    before_action :set_chat

    def index
      @chat_messages = @chat.chat_messages.order(sent_at: :desc).page(params[:page]).per(params[:per_page] || 50)
    end

    def create
      @chat_message = @chat.chat_messages.new(chat_message_params)
      @chat_message.save!
      @message = 'Message sent'
      render :show, status: :created
    end

    private

    def set_chat
      @chat = RawWb::Chat.find(params[:chat_id])
    end

    def chat_message_params
      params.require(:chat_message).permit(:sender, :text, :file_id, :sent_at)
    end
  end
end
