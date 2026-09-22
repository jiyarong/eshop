class AddIsLatestToEcAISkuOperationPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_ai_sku_operation_plans, :is_latest, :boolean, null: false, default: true
    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE ec_ai_sku_operation_plans AS plans
          SET is_latest = false
          WHERE EXISTS (
            SELECT 1 FROM ec_ai_sku_operation_plans AS newer
            WHERE newer.sku_id = plans.sku_id
              AND (newer.created_at AT TIME ZONE 'Asia/Shanghai')::date >
                  (plans.created_at AT TIME ZONE 'Asia/Shanghai')::date
          )
        SQL
      end
    end
  end
end
