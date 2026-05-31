class CreateRawWbAdSettledFees < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_ad_settled_fees do |t|
      t.bigint  :account_id,   null: false
      t.bigint  :advert_id,    null: false    # wb_advert_id
      t.string  :camp_name
      t.string  :payment_type
      t.decimal :upd_sum_rub,  precision: 15, scale: 4, default: 0
      t.date    :date_from,    null: false
      t.date    :date_to,      null: false
      t.datetime :synced_at

      t.timestamps
    end

    add_index :raw_wb_ad_settled_fees, [:account_id, :advert_id, :date_from, :date_to],
              unique: true, name: 'idx_raw_wb_ad_settled_fees_unique'
    add_index :raw_wb_ad_settled_fees, [:account_id, :date_from],
              name: 'idx_raw_wb_ad_settled_fees_account_date'

    add_foreign_key :raw_wb_ad_settled_fees, :raw_wb_seller_accounts, column: :account_id
  end
end
