class CreateEcAISkuOperationPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_ai_sku_operation_plans do |t|
      t.references :sku, null: false, foreign_key: { to_table: :ec_skus }
      t.string :target, null: false
      t.string :operation, null: false
      t.jsonb :referer, null: false, default: []
      t.text :message, null: false
      t.string :status, null: false, default: "active"
      t.datetime :retain_until, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ec_ai_sku_operation_plans, [ :sku_id, :status ]
    add_index :ec_ai_sku_operation_plans, :retain_until
  end
end
