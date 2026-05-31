class CreateEcInventorySnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_inventory_snapshots do |t|
      t.string  :sku_code,    null: false
      t.string  :platform,    null: false  # 'ozon' / 'wb'
      t.integer :account_id,  null: false  # raw_ozon/raw_wb seller_account id
      t.string  :store_name                # 可读名称，冗余存储方便查询

      t.integer :stock,   default: 0, null: false  # 当前库存
      t.integer :supply,  default: 0, null: false  # 累计送仓
      t.integer :sold,    default: 0, null: false  # 售出（supply - stock）
      t.integer :fbs,     default: 0, null: false  # FBS/DBS 销量

      t.datetime :synced_at
      t.timestamps
    end

    add_index :ec_inventory_snapshots, [:sku_code, :platform, :account_id],
              unique: true, name: 'idx_ec_inventory_snapshots_unique'
    add_index :ec_inventory_snapshots, :sku_code
  end
end
