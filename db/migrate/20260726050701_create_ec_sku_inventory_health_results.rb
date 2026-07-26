class CreateEcSkuInventoryHealthResults < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_sku_inventory_health_results do |t|
      t.references :sku, null: false, foreign_key: { to_table: :ec_skus }
      t.references :submitted_by, null: false, foreign_key: { to_table: :users }
      t.datetime :analyzed_at
      t.jsonb :classification, null: false, default: {}
      t.jsonb :metrics, null: false, default: {}
      t.jsonb :events, null: false, default: []

      t.timestamps
    end

    add_index :ec_sku_inventory_health_results, [ :sku_id, :created_at ]
  end
end
