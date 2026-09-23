class AddPlanToEcOperationActions < ActiveRecord::Migration[8.1]
  def change
    add_reference :ec_operation_actions, :plan, foreign_key: { to_table: :ec_ai_sku_operation_plans, on_delete: :nullify }
  end
end
