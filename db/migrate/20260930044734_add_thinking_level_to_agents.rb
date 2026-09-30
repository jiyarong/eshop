class AddThinkingLevelToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :thinking_level, :string, default: "", null: false
  end
end
