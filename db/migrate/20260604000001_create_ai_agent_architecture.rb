class CreateAIAgentArchitecture < ActiveRecord::Migration[8.0]
  def change
    create_table :agents do |t|
      t.string :name, null: false
      t.text :system_prompt, null: false
      t.string :model_id, null: false
      t.decimal :temperature, precision: 3, scale: 2, null: false, default: 0.3
      t.jsonb :tools, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    add_index :agents, :enabled
    add_index :agents, :name

    create_table :conversations do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :module_name
      t.string :business_object_type
      t.string :business_object_id
      t.jsonb :time_range, null: false, default: {}
      t.jsonb :context, null: false, default: {}
      t.timestamps
    end

    add_index :conversations, [:user_id, :created_at]
    add_index :conversations, [:module_name, :business_object_type, :business_object_id],
              name: "idx_conversations_on_erp_context"

    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.jsonb :usage, null: false, default: {}
      t.timestamps
    end

    add_index :messages, [:conversation_id, :created_at]
    add_index :messages, :role
  end
end
