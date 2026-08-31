class CreateRawOzonSupplyOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_ozon_supply_order_items do |t|
      t.references :supply_order, null: false, foreign_key: { to_table: :raw_ozon_supply_orders }
      t.bigint :ozon_supply_id, null: false
      t.string :bundle_id, null: false
      t.string :state
      t.bigint :platform_sku_id, null: false
      t.integer :quantity, null: false, default: 0
      t.bigint :macrolocal_cluster_id
      t.bigint :storage_warehouse_id
      t.string :storage_warehouse_name
      t.string :storage_warehouse_address
      t.boolean :is_crossdock
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at

      t.timestamps

      t.index [:supply_order_id, :bundle_id, :platform_sku_id],
        unique: true, name: "idx_raw_ozon_supply_order_items_unique"
      t.index [:platform_sku_id, :supply_order_id],
        name: "idx_raw_ozon_supply_order_items_sku_order"
      t.index :ozon_supply_id
    end
  end
end
