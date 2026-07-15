class AddAgentTypeToAgents < ActiveRecord::Migration[8.1]
  def up
    add_column :agents, :agent_type, :string, null: false, default: "web"
    add_index :agents, :agent_type
    add_check_constraint :agents,
      "agent_type IN ('web', 'client')",
      name: "agents_agent_type_check"

    execute <<~SQL.squish
      UPDATE agents
      SET agent_type = 'client'
      WHERE EXISTS (
        SELECT 1
        FROM agent_skills
        WHERE agent_skills.agent_id = agents.id
      )
    SQL
  end

  def down
    remove_check_constraint :agents, name: "agents_agent_type_check"
    remove_index :agents, :agent_type
    remove_column :agents, :agent_type
  end
end
