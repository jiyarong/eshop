class CreateEcSkuPlanningCycles < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_sku_planning_cycles do |t|
      t.references :sku, null: false, foreign_key: { to_table: :ec_skus }
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :status, null: false, default: "pending"
      t.integer :revision, null: false, default: 1
      t.boolean :is_current, null: false, default: true
      t.references :planner_conversation, foreign_key: { to_table: :conversations }
      t.jsonb :diagnosis_event_ids, null: false, default: []
      t.string :context_version
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.timestamps
    end

    add_index :ec_sku_planning_cycles,
      [ :sku_id, :period_start, :revision ],
      unique: true,
      name: "idx_sku_planning_cycles_on_sku_period_revision"
    add_index :ec_sku_planning_cycles,
      [ :sku_id, :period_start ],
      unique: true,
      where: "is_current",
      name: "idx_current_sku_planning_cycle"
    add_index :ec_sku_planning_cycles, [ :period_start, :period_end ], name: "idx_sku_planning_cycles_on_period"

    add_reference :ec_ai_sku_operation_plans, :planning_cycle,
      foreign_key: { to_table: :ec_sku_planning_cycles },
      index: true
  end
end
