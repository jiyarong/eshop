module Api
  class ConversationsController < BaseController
    def show
      conversation = Conversation.includes(:agent, :messages).find(params[:id])

      render json: {
        success: true,
        data: {
          id: conversation.id,
          agent: {
            id: conversation.agent.id,
            code: conversation.agent.code,
            name: conversation.agent.name
          },
          module_name: conversation.module_name,
          business_object_type: conversation.business_object_type,
          business_object_id: conversation.business_object_id,
          time_range: conversation.time_range,
          context: conversation.context,
          created_at: conversation.created_at.iso8601(3),
          updated_at: conversation.updated_at.iso8601(3),
          messages: conversation.messages.order(:created_at, :id).map { |message| serialize_message(message) }
        }
      }
    end

    private

    def serialize_message(message)
      {
        id: message.id,
        role: message.role,
        content: message.content,
        usage: message.usage,
        created_at: message.created_at.iso8601(3),
        updated_at: message.updated_at.iso8601(3)
      }
    end
  end
end
