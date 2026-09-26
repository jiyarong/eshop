module ErpAI
  class ConversationsController < ApplicationController
    PAGE_SIZE = 30
    before_action :authenticate_user!
    before_action -> { require_permission!(:view_reports) }

    def index
      @agents = Agent.available_for_conversation.order(:name)
      @conversations = current_user.conversations.includes(:agent).order(created_at: :desc, id: :desc).page(params[:page]).per(PAGE_SIZE)
      @first_messages = Message.where(conversation_id: @conversations.map(&:id), role: "user")
        .order(:created_at, :id).group_by(&:conversation_id).transform_values(&:first)
    end

    def create
      if request.format.html?
        agent = Agent.available_for_conversation.find_by!(code: params[:agent_code])
        conversation = agent.conversations.create!(user: current_user)
        return redirect_to ai_conversation_path(conversation)
      end

      if conversation_params[:agent_code].in?(Agent::SCHEDULED_ONLY_CODES)
        return render json: { error: "#{conversation_params[:agent_code]} is scheduled-only" }, status: :unprocessable_entity
      end

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

    def show
      @conversation = Conversation.includes(:agent, :user).find(params[:id])
      @linked_event = Ec::AIDiagnosisEvent
        .includes(ai_diagnosis: :sku)
        .find_by(conversation_id: @conversation.id)

      @messages = @conversation.messages.with_attached_images.order(:created_at, :id)
      @message = @conversation.messages.new
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
