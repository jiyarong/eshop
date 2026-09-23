class AddPlanDateToEcAISkuOperationPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_ai_sku_operation_plans, :plan_date, :date
    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE ec_ai_sku_operation_plans
          SET plan_date = (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Shanghai')::date
        SQL
      end
    end
    change_column_null :ec_ai_sku_operation_plans, :plan_date, false
    add_index :ec_ai_sku_operation_plans, [ :sku_id, :plan_date ]
  end
end
