class CreateEcSkuLifecycleEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_sku_lifecycle_events do |t|
      t.references :sku, null: false, foreign_key: { to_table: :ec_skus }
      t.references :sku_product, null: true, foreign_key: { to_table: :ec_sku_products }
      t.string :event_type, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :content, null: false, default: {}
      t.string :source_type
      t.bigint :source_id
      t.string :source_key, null: false

      t.timestamps
    end

    add_index :ec_sku_lifecycle_events, :source_key, unique: true
    add_index :ec_sku_lifecycle_events, [ :sku_id, :occurred_at ]
    add_index :ec_sku_lifecycle_events, [ :sku_product_id, :occurred_at ]
    add_index :ec_sku_lifecycle_events, [ :event_type, :occurred_at ]
  end
end
