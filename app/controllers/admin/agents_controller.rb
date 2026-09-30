module Admin
  class AgentsController < BaseController
    before_action :seed_fixed_agents
    before_action :set_agent, only: [ :edit, :update, :destroy ]
    before_action :load_capabilities, only: [ :new, :create, :edit, :update ]

    def index
      @status = params[:status].presence_in(%w[enabled disabled])
      @agent_type = params[:agent_type].presence_in(Agent.agent_types.keys)
      @agents = Agent.order(:code)
      @agents = @agents.where(enabled: @status == "enabled") if @status.present?
      @agents = @agents.where(agent_type: @agent_type) if @agent_type.present?
    end

    def edit
    end

    def new
      @agent = Agent.new(
        agent_type: :web,
        enabled: true,
        model_id: "deepseek-v4-flash",
        temperature: 0.3,
        system_prompt: Agent::GENERAL_AGENT_PROMPT
      )
    end

    def create
      @agent = Agent.new(agent_params.merge(code: create_code))

      if @agent.save
        redirect_to admin_agents_path, notice: t("admin.agents.notices.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @agent.update(agent_params)
        redirect_to admin_agents_path, notice: t("admin.agents.notices.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      raise ActiveRecord::RecordNotFound unless @agent.deletable?

      @agent.destroy!
      redirect_to admin_agents_path, notice: t("admin.agents.notices.deleted")
    end

    private

    def seed_fixed_agents
      Agent.seed_fixed!
    end

    def set_agent
      @agent = Agent.find_by!(code: params[:id])
    end

    def agent_params
      permitted = params.require(:agent).permit(
        :name,
        :description,
        :system_prompt,
        :model_id,
        :temperature,
        :agent_type,
        :thinking_enabled,
        :thinking_level,
        :enabled,
        :avatar,
        tools: [],
        skill_ids: []
      )
      permitted[:recommended_prompts] = recommended_prompts
      permitted[:tools] = Array(permitted[:tools]).reject(&:blank?) if permitted.key?(:tools)
      permitted[:skill_ids] = [] if permitted[:agent_type] == "web"
      permitted[:tools] = [] if permitted[:agent_type] == "client"
      permitted
    end

    def create_code
      params.require(:agent).permit(:code).fetch(:code)
    end

    def recommended_prompts
      params.require(:agent).permit(:recommended_prompts_text)[:recommended_prompts_text]
        .to_s.lines.map(&:strip).reject(&:blank?)
    end

    def load_capabilities
      @skills = Skill.order(:name)
      @tools = ErpAI::ToolRegistry.default_tools
      if @agent&.code == "sku_diagnosis"
        @tools = @tools.select { |tool| tool.fetch(:name) == "save_sku_event" }
      elsif @agent&.code == "sku_planner"
        @tools = @tools.select { |tool| tool.fetch(:name) == "save_sku_plan" }
      else
        @tools = @tools.reject { |tool| tool.fetch(:name) == "save_sku_plan" }
        @tools += ErpAI::ToolRegistry.optional_mcp_tools unless @agent&.code == "page_translation"
      end
    end
  end
end
