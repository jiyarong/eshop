module RawWb
  class ChatsController < BaseController
    before_action :set_chat,  only: [:show, :update, :destroy]

    def index
      @chats = RawWb::Chat.all
      @chats = @chats.where(account_id: params[:account_id]) if params[:account_id].present?
      @chats = @chats.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @chat = RawWb::Chat.new(chat_params)
      @chat.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @chat.update!(chat_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @chat.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_chat
      @chat = RawWb::Chat.find(params[:id])
    end

    def chat_params
      params.require(:chat).permit!
    end
  end
end
