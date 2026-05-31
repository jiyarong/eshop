class CreateRawOzonFinance < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_finance_transactions do |t|
      t.references :account,        null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint  :operation_id,      null: false
      t.string  :operation_type
      t.string  :operation_type_name
      t.string  :posting_number
      t.string  :order_number
      t.decimal :amount,            precision: 18, scale: 2
      t.string  :currency_code,     default: 'RUB'
      t.decimal :accruals_for_sale, precision: 18, scale: 2
      t.decimal :sale_commission,   precision: 18, scale: 2
      t.decimal :delivery_charge,   precision: 18, scale: 2
      t.decimal :return_delivery_charge, precision: 18, scale: 2
      t.jsonb   :items
      t.jsonb   :services
      t.jsonb   :raw_json,          null: false
      t.datetime :operation_date
      t.datetime :order_date
      t.datetime :synced_at
      t.index [:account_id, :operation_id], unique: true
      t.index [:account_id, :operation_date]
      t.index [:account_id, :operation_type]
      t.index [:account_id, :posting_number]
    end

    create_table :raw_ozon_finance_realizations do |t|
      t.references :account,        null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.date    :report_date,       null: false
      t.string  :doc_number
      t.date    :doc_date
      t.decimal :accruals_for_sale,   precision: 18, scale: 2
      t.decimal :compensation_amount, precision: 18, scale: 2
      t.decimal :money_transfer,      precision: 18, scale: 2
      t.decimal :total_amount,        precision: 18, scale: 2
      t.decimal :start_balance,       precision: 18, scale: 2
      t.decimal :close_balance,       precision: 18, scale: 2
      t.jsonb   :rows
      t.jsonb   :raw_json,          null: false
      t.datetime :synced_at
      t.index [:account_id, :report_date], unique: true
    end
  end
end
