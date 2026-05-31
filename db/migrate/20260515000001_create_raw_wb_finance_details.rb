class CreateRawWbFinanceDetails < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_finance_details do |t|
      t.bigint  :account_id,             null: false
      t.bigint  :rrdid,                  null: false

      t.bigint  :nm_id
      t.bigint  :shk_id
      t.string  :sa_name
      t.string  :ts_name
      t.string  :barcode
      t.string  :brand_name
      t.string  :subject_name

      t.string  :seller_oper_name,       null: false, default: ''
      t.integer :report_type

      t.decimal :retail_price,           precision: 15, scale: 2
      t.decimal :retail_price_with_disc, precision: 15, scale: 2
      t.decimal :retail_amount,          precision: 15, scale: 2
      t.integer :sale_percent
      t.decimal :commission_percent,     precision: 10, scale: 4

      t.decimal :for_pay,                precision: 15, scale: 2
      t.decimal :acquiring_fee,          precision: 15, scale: 2
      t.decimal :delivery_rub,           precision: 15, scale: 2
      t.decimal :rebill_logistic_cost,   precision: 15, scale: 2
      t.decimal :ppvz_reward,            precision: 15, scale: 2
      t.decimal :penalty,                precision: 15, scale: 2
      t.decimal :paid_storage,           precision: 15, scale: 2
      t.decimal :deduction,              precision: 15, scale: 2

      t.integer  :quantity
      t.string   :doc_type
      t.string   :srid
      t.date     :order_dt
      t.date     :sale_dt
      t.datetime :synced_at

      t.timestamps
    end

    add_index :raw_wb_finance_details, [:account_id, :rrdid],
              unique: true, name: 'idx_raw_wb_finance_details_unique'
    add_index :raw_wb_finance_details, [:account_id, :nm_id, :sale_dt],
              name: 'idx_raw_wb_finance_details_nm_sale'
    add_index :raw_wb_finance_details, [:account_id, :shk_id],
              name: 'idx_raw_wb_finance_details_shk'

    add_foreign_key :raw_wb_finance_details, :raw_wb_seller_accounts, column: :account_id
  end
end