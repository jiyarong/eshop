class CreateRawWbAnalytics < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_analytics_sales_funnels do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.date :stat_date, null: false
      t.bigint :nm_id
      t.string :vendor_code
      t.string :brand
      t.string :subject
      t.bigint :open_card, default: 0
      t.bigint :add_to_cart, default: 0
      t.bigint :orders, default: 0
      t.decimal :orders_sum, precision: 15, scale: 2
      t.bigint :buyouts, default: 0
      t.decimal :buyouts_sum, precision: 15, scale: 2
      t.bigint :cancel_count, default: 0
      t.decimal :cancel_sum, precision: 15, scale: 2
      t.decimal :conv_to_cart, precision: 10, scale: 4
      t.decimal :cart_to_order, precision: 10, scale: 4
      t.index [:account_id, :stat_date, :nm_id], unique: true
    end

    create_table :raw_wb_analytics_search_terms do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.date :stat_date, null: false
      t.string :keyword
      t.bigint :nm_id
      t.bigint :orders, default: 0
      t.decimal :avg_position, precision: 10, scale: 2
      t.bigint :frequency
      t.index [:account_id, :stat_date, :keyword, :nm_id], unique: true, name: 'idx_raw_wb_search_terms_unique'
    end
  end
end
