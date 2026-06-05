module Admin
  class AgentsController < BaseController
    before_action :seed_fixed_agents
    before_action :set_agent, only: [:edit, :update]

    def index
      @agents = Agent.order(:code)
    end

    def edit
    end

    def update
      if @agent.update(agent_params)
        redirect_to admin_agents_path
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
      params.require(:agent).permit(:system_prompt, :model_id, :temperature)
    end
  end
end
