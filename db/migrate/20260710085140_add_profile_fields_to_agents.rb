class AddProfileFieldsToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :description, :text, null: false, default: ""
    add_column :agents, :recommended_prompts, :jsonb, null: false, default: []
  end
end
