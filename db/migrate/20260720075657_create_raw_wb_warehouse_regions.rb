class CreateRawWbWarehouseRegions < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_wb_warehouse_regions do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.bigint :warehouse_id, null: false
      t.string :warehouse_name, null: false
      t.string :normalized_warehouse_name, null: false
      t.string :region_name, null: false
      t.string :source, null: false
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false

      t.timestamps
    end

    add_index :raw_wb_warehouse_regions,
      [:account_id, :warehouse_id],
      unique: true,
      name: "idx_raw_wb_warehouse_regions_unique"
    add_index :raw_wb_warehouse_regions,
      [:account_id, :normalized_warehouse_name],
      name: "idx_raw_wb_warehouse_regions_lookup"
  end
end
