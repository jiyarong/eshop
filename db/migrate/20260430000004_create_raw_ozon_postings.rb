class CreateRawOzonPostings < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_postings_fbs do |t|
      t.references :account,              null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string  :posting_number,          null: false
      t.bigint  :order_id
      t.string  :order_number
      t.string  :parent_posting_number
      t.string  :status,                  null: false
      t.string  :substatus
      t.bigint  :delivery_method_id
      t.string  :delivery_method_name
      t.string  :tpl_integration_type
      t.string  :tracking_number
      t.boolean :is_express,              default: false
      t.boolean :is_multibox,             default: false
      t.integer :multi_box_qty,           default: 1
      t.bigint  :customer_id
      t.string  :addressee_name
      t.jsonb   :financial_data
      t.jsonb   :analytics_data
      t.jsonb   :requirements
      t.jsonb   :cancellation
      t.jsonb   :raw_json,                null: false
      t.datetime :in_process_at
      t.datetime :shipment_date
      t.datetime :shipment_date_without_delay
      t.datetime :delivering_date
      t.datetime :created_at,             null: false
      t.datetime :synced_at
      t.index [:account_id, :posting_number], unique: true
      t.index [:account_id, :status]
      t.index [:account_id, :created_at]
      t.index [:account_id, :order_id]
    end

    create_table :raw_ozon_postings_fbo do |t|
      t.references :account,     null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string  :posting_number, null: false
      t.bigint  :order_id
      t.string  :order_number
      t.string  :status,         null: false
      t.string  :substatus
      t.integer :cancel_reason_id
      t.jsonb   :financial_data
      t.jsonb   :analytics_data
      t.jsonb   :additional_data
      t.jsonb   :raw_json,       null: false
      t.datetime :in_process_at
      t.datetime :fact_delivery_date
      t.datetime :created_at,    null: false
      t.datetime :synced_at
      t.index [:account_id, :posting_number], unique: true
      t.index [:account_id, :status]
      t.index [:account_id, :created_at]
    end

    create_table :raw_ozon_posting_items do |t|
      t.references :account,     null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string  :posting_number, null: false
      t.string  :posting_type,   null: false  # 'fbs' | 'fbo'
      t.bigint  :ozon_sku
      t.string  :offer_id
      t.string  :name
      t.integer :quantity,       null: false, default: 1
      t.decimal :price,          precision: 18, scale: 2
      t.decimal :old_price,      precision: 18, scale: 2
      t.string  :currency_code
      t.decimal :payout,         precision: 18, scale: 2
      t.decimal :commission_amount, precision: 18, scale: 2
      t.decimal :commission_percent, precision: 5, scale: 2
      t.jsonb   :raw_json,       null: false
      t.datetime :synced_at
      t.index [:account_id, :posting_number]
      t.index [:account_id, :ozon_sku]
      t.index [:account_id, :offer_id]
    end
  end
end
