class CreateEcSkuInventoryLevels < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_sku_inventory_levels do |t|
      t.string :sku_code, null: false
      t.string :platform, null: false
      t.integer :account_id, null: false
      t.bigint :store_id
      t.string :store_name
      t.string :fulfillment_type, null: false
      t.integer :quantity, default: 0, null: false
      t.boolean :is_latest, default: true, null: false
      t.datetime :synced_at, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :ec_sku_inventory_levels, :sku_code
    add_index :ec_sku_inventory_levels, [:sku_code, :platform, :account_id, :fulfillment_type, :synced_at],
      name: "idx_ec_sku_inventory_levels_history"
    add_index :ec_sku_inventory_levels, [:sku_code, :platform, :account_id, :fulfillment_type],
      unique: true,
      where: "is_latest",
      name: "idx_ec_sku_inventory_levels_latest"
    add_foreign_key :ec_sku_inventory_levels, :ec_stores, column: :store_id
  end
end
