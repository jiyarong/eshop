class CreateRawOzonPostingReportItemsAndAddBuyerPaidToOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_ozon_posting_report_items do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.references :report, null: true, foreign_key: { to_table: :raw_ozon_reports }
      t.references :ec_order_item, null: true, index: false, foreign_key: { to_table: :ec_order_items }
      t.string :delivery_schema, null: false
      t.string :order_number
      t.string :posting_number, null: false
      t.datetime :processed_at
      t.bigint :ozon_sku, null: false
      t.string :offer_id
      t.integer :quantity, null: false
      t.decimal :seller_unit_price, precision: 18, scale: 2
      t.string :seller_currency_code
      t.decimal :buyer_paid_unit_price, precision: 18, scale: 2
      t.string :buyer_currency_code
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps
    end

    add_index :raw_ozon_posting_report_items, %i[account_id delivery_schema posting_number ozon_sku], unique: true, name: "idx_raw_ozon_posting_report_items_identity"
    add_index :raw_ozon_posting_report_items, :ec_order_item_id, unique: true, where: "ec_order_item_id IS NOT NULL", name: "idx_raw_ozon_posting_report_items_order_item"
    add_index :raw_ozon_posting_report_items, %i[account_id processed_at], name: "idx_raw_ozon_posting_report_items_processed"
    add_index :raw_ozon_posting_report_items, %i[account_id offer_id], name: "idx_raw_ozon_posting_report_items_offer"

    add_column :ec_order_items, :buyer_paid_unit_price, :decimal, precision: 18, scale: 2
    add_column :ec_order_items, :buyer_currency_code, :string
    add_column :ec_order_items, :buyer_paid_synced_at, :datetime
  end
end
