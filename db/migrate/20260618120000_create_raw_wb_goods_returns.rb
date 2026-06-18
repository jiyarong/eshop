class CreateRawWbGoodsReturns < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_goods_returns do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.bigint  :shk_id,             null: false
      t.bigint  :order_id
      t.bigint  :nm_id
      t.string  :barcode
      t.string  :brand
      t.string  :subject_name
      t.string  :tech_size
      t.string  :return_type
      t.string  :reason
      t.string  :status
      t.integer :is_status_active
      t.string  :srid
      t.string  :sticker_id
      t.date    :order_dt
      t.datetime :ready_to_return_dt
      t.datetime :completed_dt
      t.datetime :expired_dt
      t.integer :dst_office_id
      t.string  :dst_office_address
      t.datetime :synced_at

      t.index [:account_id, :shk_id], unique: true
      t.index :order_id
      t.index :nm_id
    end
  end
end