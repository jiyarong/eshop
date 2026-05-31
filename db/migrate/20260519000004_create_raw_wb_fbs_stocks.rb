class CreateRawWbFbsStocks < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_fbs_stocks do |t|
      t.integer  :account_id, null: false
      t.string   :barcode,    null: false
      t.bigint   :nm_id
      t.integer  :amount,     null: false, default: 0
      t.datetime :synced_at
      t.timestamps
    end

    add_index :raw_wb_fbs_stocks, [:account_id, :barcode],
              unique: true, name: 'idx_raw_wb_fbs_stocks_unique'
    add_index :raw_wb_fbs_stocks, [:account_id, :nm_id]
  end
end
