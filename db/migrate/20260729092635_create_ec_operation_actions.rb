class CreateEcOperationActions < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_operation_actions do |t|
      t.string :operation_type, null: false
      t.references :operated_by_user, null: false, foreign_key: { to_table: :users }
      t.datetime :operated_at, null: false
      t.references :ec_sku_product, null: false, foreign_key: true
      t.references :ec_sku, null: false, foreign_key: true
      t.references :ec_store, null: false, foreign_key: true
      t.jsonb :diff_result, null: false, default: {}
      t.boolean :record_by_system, null: false, default: true

      t.timestamps
    end

    add_index :ec_operation_actions, [:ec_sku_product_id, :operated_at], name: "idx_ec_operation_actions_listing_time"
    add_index :ec_operation_actions, [:operation_type, :operated_at], name: "idx_ec_operation_actions_type_time"
  end
end
