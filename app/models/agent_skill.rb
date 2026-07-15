class AgentSkill < ApplicationRecord
  belongs_to :agent
  belongs_to :skill

  validates :skill_id, uniqueness: { scope: :agent_id }
  validate :agent_accepts_skills

  private

  def agent_accepts_skills
    return if agent.blank? || agent.client?

    errors.add(:agent, I18n.t("admin.agents.errors.skills_unavailable_for_web"))
  end
end
