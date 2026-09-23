class AddDetailsToEcAISkuOperationPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_ai_sku_operation_plans, :scope, :string
    add_column :ec_ai_sku_operation_plans, :scope_id, :string
    add_column :ec_ai_sku_operation_plans, :priority, :integer
    add_column :ec_ai_sku_operation_plans, :reason, :text
    add_column :ec_ai_sku_operation_plans, :baseline, :text
    add_column :ec_ai_sku_operation_plans, :constraints, :text
    add_column :ec_ai_sku_operation_plans, :expected_effect, :text
  end
end
