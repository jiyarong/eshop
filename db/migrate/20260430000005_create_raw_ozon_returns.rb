class CreateRawOzonReturns < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_returns do |t|
      t.references :account,     null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint  :return_id,      null: false
      t.string  :return_schema,  null: false  # 'FBS' | 'FBO'
      t.string  :return_type                  # 'Cancellation' | 'Return'
      t.string  :return_reason_name
      t.string  :posting_number
      t.bigint  :order_id
      t.string  :order_number
      t.bigint  :ozon_sku
      t.string  :offer_id
      t.string  :product_name
      t.integer :quantity,       default: 1
      t.decimal :price,          precision: 18, scale: 2
      t.jsonb   :place
      t.jsonb   :target_place
      t.jsonb   :storage
      t.string  :visual_status
      t.jsonb   :compensation_status
      t.jsonb   :raw_json,       null: false
      t.datetime :synced_at
      t.index [:account_id, :return_id], unique: true
      t.index [:account_id, :return_schema]
      t.index [:account_id, :posting_number]
      t.index [:account_id, :visual_status]
    end
  end
end
