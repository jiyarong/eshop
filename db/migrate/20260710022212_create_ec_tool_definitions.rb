class CreateEcToolDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_tool_definitions do |t|
      t.string :tool_type, null: false
      t.integer :version, null: false
      t.string :name, null: false
      t.string :slug, null: false
      t.string :renderer_key, null: false
      t.jsonb :schema_json, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :ec_tool_definitions, [:tool_type, :version], unique: true
    add_index :ec_tool_definitions, [:tool_type, :active, :version], name: "idx_ec_tool_definitions_lookup"
    add_index :ec_tool_definitions, :slug, unique: true
  end
end
