class AgentSkill < ApplicationRecord
  belongs_to :agent
  belongs_to :skill

  validates :skill_id, uniqueness: { scope: :agent_id }
end
