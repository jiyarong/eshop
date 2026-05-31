class CreateRawWbSupplyItems < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_supply_items do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.string  :wb_supply_id,   null: false
      t.bigint  :nm_id,          null: false
      t.integer :quantity,       null: false, default: 0
      t.integer :accepted_qty,   null: false, default: 0
      t.datetime :synced_at

      t.index [:account_id, :wb_supply_id, :nm_id],
              unique: true,
              name: 'idx_raw_wb_supply_items_unique'
      t.index [:account_id, :nm_id]
    end
  end
end
