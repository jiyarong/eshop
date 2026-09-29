class CreateEcAISkuOperationPlanEvaluations < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_ai_sku_operation_plan_evaluations do |t|
      t.references :plan, null: false, foreign_key: { to_table: :ec_ai_sku_operation_plans }
      t.date :observation_from, null: false
      t.date :observation_to, null: false
      t.string :execution_status, null: false
      t.string :effectiveness, null: false
      t.string :confidence, null: false
      t.text :summary, null: false
      t.jsonb :metrics, null: false, default: {}
      t.jsonb :evidence, null: false, default: {}
      t.jsonb :action_ids, null: false, default: []
      t.references :conversation, foreign_key: true
      t.string :evaluator_version, null: false
      t.string :status, null: false, default: "succeeded"
      t.datetime :evaluated_at

      t.timestamps
    end

    add_index :ec_ai_sku_operation_plan_evaluations, [ :plan_id, :observation_to ], unique: true,
      name: "idx_plan_evaluations_on_plan_and_observation_to"
    add_index :ec_ai_sku_operation_plan_evaluations, [ :status, :observation_to ],
      name: "idx_plan_evaluations_on_status_and_observation_to"
  end
end
