class CreateRawWbPaidStorages < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_paid_storages do |t|
      t.bigint  :account_id,          null: false
      t.bigint  :nm_id,               null: false
      t.string  :vendor_code
      # 按 (nm_id, calc_date) 预聚合：warehousePrice 是该 nmId 当天所有仓库的合计费用
      t.decimal :warehouse_price_rub,  precision: 15, scale: 4, default: 0
      t.date    :calc_date,           null: false
      t.datetime :synced_at

      t.timestamps
    end

    add_index :raw_wb_paid_storages, [:account_id, :nm_id, :calc_date],
              unique: true, name: 'idx_raw_wb_paid_storages_unique'
    add_index :raw_wb_paid_storages, [:account_id, :calc_date],
              name: 'idx_raw_wb_paid_storages_account_date'

    add_foreign_key :raw_wb_paid_storages, :raw_wb_seller_accounts, column: :account_id
  end
end
