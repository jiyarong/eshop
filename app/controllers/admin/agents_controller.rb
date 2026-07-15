module Admin
  class AgentsController < BaseController
    before_action :seed_fixed_agents
    before_action :set_agent, only: [ :edit, :update ]
    before_action :load_skills, only: [ :new, :create, :edit, :update ]

    def index
      @agents = Agent.includes(:skills).order(:code)
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
      @agent = Agent.new(agent_params.merge(code: create_code, tools: []))

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
        :enabled,
        :avatar,
        skill_ids: []
      )
      permitted[:recommended_prompts] = recommended_prompts
      permitted[:skill_ids] = [] if permitted[:agent_type] == "web"
      permitted
    end

    def create_code
      params.require(:agent).permit(:code).fetch(:code)
    end

    def recommended_prompts
      params.require(:agent).permit(:recommended_prompts_text)[:recommended_prompts_text]
        .to_s.lines.map(&:strip).reject(&:blank?)
    end

    def load_skills
      @skills = Skill.order(:name)
    end
  end
end
