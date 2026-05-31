class CreateEcInventoryTotals < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_inventory_totals do |t|
      t.string  :sku_code, null: false

      # 运营手填（通过 Google Sheets）
      t.integer :total_received, default: 0, null: false  # 总入库

      # 聚合快照（由 sync 写入，避免每次查询都聚合）
      t.integer :total_supply, default: 0, null: false
      t.integer :total_stock,  default: 0, null: false
      t.integer :total_sold,   default: 0, null: false
      t.integer :total_fbs,    default: 0, null: false

      t.datetime :synced_at
      t.timestamps
    end

    add_index :ec_inventory_totals, :sku_code, unique: true
  end
end
