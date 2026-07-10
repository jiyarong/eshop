class CreateEcToolConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_tool_configurations do |t|
      t.references :tool_definition, null: false, foreign_key: { to_table: :ec_tool_definitions }
      t.string :name, null: false
      t.jsonb :config_json, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :ec_tool_configurations, [:tool_definition_id, :active], name: "idx_ec_tool_configs_definition_active"
  end
end
