class AddFingerprintToEcSkuOperationPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_ai_sku_operation_plans, :fingerprint, :string
    add_index :ec_ai_sku_operation_plans, [ :planning_cycle_id, :fingerprint ], unique: true,
      where: "fingerprint IS NOT NULL AND planning_cycle_id IS NOT NULL",
      name: "idx_sku_operation_plans_on_cycle_fingerprint"
  end
end
