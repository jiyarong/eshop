class CreateRawWbFinance < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_account_balances do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.string :currency, default: 'RUB'
      t.decimal :current, precision: 15, scale: 2
      t.decimal :for_withdraw, precision: 15, scale: 2
      t.datetime :snapshot_at, default: -> { 'CURRENT_TIMESTAMP' }
    end

    create_table :raw_wb_sales_reports do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.bigint :wb_report_id, index: { unique: true }
      t.date :date_from
      t.date :date_to
      t.date :report_created_at
      t.decimal :total_sales, precision: 15, scale: 2
      t.decimal :total_returns, precision: 15, scale: 2
      t.decimal :total_commission, precision: 15, scale: 2
      t.decimal :total_delivery, precision: 15, scale: 2
      t.decimal :total_penalty, precision: 15, scale: 2
      t.decimal :net_payable, precision: 15, scale: 2
      t.datetime :synced_at
    end

    create_table :raw_wb_sales_report_items do |t|
      t.references :sales_report, null: false, foreign_key: { to_table: :raw_wb_sales_reports }
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.bigint :nm_id
      t.string :sa_name
      t.string :ts_name
      t.string :barcode
      t.string :brand_name
      t.string :subject_name
      t.string :doc_type
      t.integer :quantity
      t.decimal :retail_price, precision: 15, scale: 2
      t.decimal :retail_amount, precision: 15, scale: 2
      t.integer :sale_percent
      t.decimal :commission_percent, precision: 10, scale: 4
      t.decimal :delivery_rub, precision: 15, scale: 2
      t.decimal :penalty, precision: 15, scale: 2
      t.decimal :additional_payment, precision: 15, scale: 2
      t.decimal :ppvz_for_pay, precision: 15, scale: 2
      t.string :srid
      t.datetime :order_dt
      t.datetime :sale_dt
    end

    create_table :raw_wb_stats_orders do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.string :g_number
      t.datetime :order_date, null: false
      t.datetime :last_change_date
      t.string :supplier_article
      t.string :tech_size
      t.string :barcode
      t.decimal :total_price, precision: 15, scale: 2
      t.integer :discount_percent
      t.string :warehouse_name
      t.string :oblast
      t.bigint :nm_id
      t.string :subject
      t.string :category
      t.string :brand
      t.boolean :is_cancel, default: false
      t.datetime :cancel_date
      t.string :order_type
      t.string :srid
      t.datetime :synced_at
    end

    create_table :raw_wb_stats_sales do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.string :g_number
      t.datetime :sale_date, null: false
      t.datetime :last_change_date
      t.string :supplier_article
      t.string :tech_size
      t.string :barcode
      t.decimal :total_price, precision: 15, scale: 2
      t.integer :discount_percent
      t.decimal :for_pay, precision: 15, scale: 2
      t.decimal :finished_price, precision: 15, scale: 2
      t.decimal :price_with_disc, precision: 15, scale: 2
      t.bigint :nm_id
      t.string :subject
      t.string :category
      t.string :brand
      t.boolean :is_storno, default: false
      t.string :srid
      t.datetime :synced_at
    end

    create_table :raw_wb_sync_tasks do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.string :task_type
      t.string :wb_task_id
      t.string :status, default: 'pending'
      t.text :file_url
      t.datetime :completed_at
      t.timestamps
    end
  end
end
