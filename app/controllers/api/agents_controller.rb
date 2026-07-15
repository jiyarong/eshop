module Api
  class AgentsController < BaseController
    def index
      Agent.seed_fixed!
      agents = Agent.enabled.client.includes(:skills, avatar_attachment: :blob).order(:id)
      skills = Skill.includes(archive_attachment: :blob).order(:name)

      render json: {
        agents: agents.map { |agent| agent_json(agent) },
        skills: skills.map { |skill| skill_json(skill) }
      }
    end

    private

    def agent_json(agent)
      {
        name: agent.name,
        description: agent.description,
        prompt: agent.system_prompt,
        model: agent.model_id,
        thinking: agent.thinking_enabled? ? "enabled" : "",
        avatar_url: agent.avatar.attached? ? rails_blob_path(agent.avatar, disposition: "inline") : nil,
        skills: agent.skills.sort_by(&:name).map(&:name),
        recommended_prompts: agent.recommended_prompts
      }
    end

    def skill_json(skill)
      {
        name: skill.name,
        description: skill.description,
        download_url: skill.archive.attached? ? rails_blob_path(skill.archive, disposition: "attachment") : nil,
        version: skill.version
      }
    end
  end
end
