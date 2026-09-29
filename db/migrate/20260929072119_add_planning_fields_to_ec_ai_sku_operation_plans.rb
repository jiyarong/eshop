class AddPlanningFieldsToEcAISkuOperationPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_ai_sku_operation_plans, :planning_period_start, :date
    add_column :ec_ai_sku_operation_plans, :planning_period_end, :date
    add_column :ec_ai_sku_operation_plans, :execution_deadline, :date
    add_column :ec_ai_sku_operation_plans, :lifecycle_status, :string, null: false, default: "active"
    add_column :ec_ai_sku_operation_plans, :execution_status, :string, null: false, default: "not_started"
    add_column :ec_ai_sku_operation_plans, :evaluation_status, :string, null: false, default: "pending"

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE ec_ai_sku_operation_plans
          SET planning_period_start = plan_date - ((EXTRACT(ISODOW FROM plan_date)::integer - 1) * INTERVAL '1 day'),
              planning_period_end = plan_date - ((EXTRACT(ISODOW FROM plan_date)::integer - 1) * INTERVAL '1 day') + INTERVAL '6 days',
              execution_deadline = plan_date - ((EXTRACT(ISODOW FROM plan_date)::integer - 1) * INTERVAL '1 day') + INTERVAL '8 days'
          WHERE planning_period_start IS NULL
        SQL
        execute "UPDATE ec_ai_sku_operation_plans SET execution_status = 'executed' WHERE status = 'done'"
        execute "UPDATE ec_ai_sku_operation_plans SET lifecycle_status = 'cancelled', execution_status = 'not_applicable' WHERE status = 'ignored'"
        execute <<~SQL.squish
          UPDATE ec_ai_sku_operation_plans
          SET retain_until = ((execution_deadline + INTERVAL '1 day') AT TIME ZONE 'Asia/Shanghai') - INTERVAL '1 microsecond'
          WHERE retain_until < ((execution_deadline + INTERVAL '1 day') AT TIME ZONE 'Asia/Shanghai')
            AND retain_until <= created_at + INTERVAL '49 hours'
        SQL
      end
    end

    change_column_null :ec_ai_sku_operation_plans, :planning_period_start, false
    change_column_null :ec_ai_sku_operation_plans, :planning_period_end, false
    change_column_null :ec_ai_sku_operation_plans, :execution_deadline, false
    add_index :ec_ai_sku_operation_plans, [ :sku_id, :planning_period_start ], name: "idx_sku_operation_plans_on_sku_and_period"
    add_index :ec_ai_sku_operation_plans, [ :planning_period_start, :planning_period_end ], name: "idx_sku_operation_plans_on_period"
  end
end
