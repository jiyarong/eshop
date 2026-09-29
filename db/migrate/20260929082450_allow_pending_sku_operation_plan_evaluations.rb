class AllowPendingSkuOperationPlanEvaluations < ActiveRecord::Migration[8.1]
  def change
    change_column_null :ec_ai_sku_operation_plan_evaluations, :execution_status, true
    change_column_null :ec_ai_sku_operation_plan_evaluations, :effectiveness, true
    change_column_null :ec_ai_sku_operation_plan_evaluations, :confidence, true
    change_column_null :ec_ai_sku_operation_plan_evaluations, :summary, true
    change_column_null :ec_ai_sku_operation_plan_evaluations, :evaluator_version, true
  end
end
