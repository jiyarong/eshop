module ErpAI
  class ConversationsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_permission!(:view_reports) }

    def create
      agent = Agent.ensure_fixed!(conversation_params[:agent_code].presence || "business_analysis")
      conversation = ErpAI::AgentRunner.new(agent: agent, user: current_user).ask(
        question: conversation_params.fetch(:question),
        module_name: conversation_params[:module_name],
        business_object_type: conversation_params[:business_object_type],
        business_object_id: conversation_params[:business_object_id],
        time_range: conversation_params[:time_range]&.to_h || {},
        data_summary: conversation_params[:data_summary]
      )

      render json: serialize_conversation(conversation), status: :created
    end

    private

    def conversation_params
      params.permit(
        :agent_code,
        :question,
        :module_name,
        :business_object_type,
        :business_object_id,
        :data_summary,
        time_range: [:from, :to]
      )
    end

    def serialize_conversation(conversation)
      assistant_message = conversation.messages.order(:created_at, :id).where(role: "assistant").last
      {
        conversation: {
          id: conversation.id,
          module_name: conversation.module_name,
          business_object_type: conversation.business_object_type,
          business_object_id: conversation.business_object_id,
          time_range: conversation.time_range
        },
        assistant_message: {
          id: assistant_message.id,
          content: assistant_message.content,
          usage: assistant_message.usage
        }
      }
    end
  end
end
