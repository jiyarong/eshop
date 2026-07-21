class CreateSalesFunnelDailyAndDropLegacySalesFunnelAnalytics < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_wb_sales_funnel_daily do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.date :stat_date, null: false
      t.string :currency, null: false, default: "RUB"
      t.bigint :nm_id, null: false
      t.string :vendor_code
      t.string :product_name
      t.string :brand
      t.bigint :subject_id
      t.string :subject
      t.jsonb :tags, null: false, default: []
      t.decimal :product_rating, precision: 5, scale: 2
      t.decimal :feedback_rating, precision: 5, scale: 2
      t.bigint :stock_wb, default: 0
      t.bigint :stock_mp, default: 0
      t.decimal :stock_balance_sum, precision: 15, scale: 2
      t.bigint :open_card, default: 0
      t.bigint :add_to_cart, default: 0
      t.bigint :orders, default: 0
      t.decimal :orders_sum, precision: 15, scale: 2
      t.bigint :buyouts, default: 0
      t.decimal :buyouts_sum, precision: 15, scale: 2
      t.bigint :cancel_count, default: 0
      t.decimal :cancel_sum, precision: 15, scale: 2
      t.decimal :avg_price, precision: 10, scale: 2
      t.decimal :avg_orders_per_day, precision: 10, scale: 4
      t.decimal :share_order_percent, precision: 10, scale: 2
      t.bigint :add_to_wishlist, default: 0
      t.integer :time_to_ready_days
      t.integer :time_to_ready_hours
      t.integer :time_to_ready_mins
      t.decimal :localization_percent, precision: 10, scale: 2
      t.decimal :conv_to_cart, precision: 10, scale: 4
      t.decimal :cart_to_order, precision: 10, scale: 4
      t.decimal :buyout_percent, precision: 10, scale: 2
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps

      t.index [:account_id, :stat_date, :nm_id], unique: true, name: "idx_raw_wb_sales_funnel_daily_unique"
      t.index :stat_date, name: "idx_raw_wb_sales_funnel_daily_date"
      t.index :nm_id, name: "idx_raw_wb_sales_funnel_daily_nm_id"
    end

    create_table :raw_ozon_sales_funnel_daily do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.date :stat_date, null: false
      t.bigint :sku, null: false
      t.string :product_name
      t.bigint :hits_view, default: 0
      t.bigint :hits_view_search, default: 0
      t.bigint :hits_view_pdp, default: 0
      t.bigint :session_view, default: 0
      t.bigint :session_view_search, default: 0
      t.bigint :session_view_pdp, default: 0
      t.bigint :hits_tocart, default: 0
      t.bigint :hits_tocart_search, default: 0
      t.bigint :hits_tocart_pdp, default: 0
      t.decimal :conv_tocart, precision: 10, scale: 4
      t.bigint :ordered_units, default: 0
      t.decimal :revenue, precision: 18, scale: 2
      t.bigint :returns_count, default: 0
      t.bigint :cancellations, default: 0
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps

      t.index [:account_id, :stat_date, :sku], unique: true, name: "idx_raw_ozon_sales_funnel_daily_unique"
      t.index :stat_date, name: "idx_raw_ozon_sales_funnel_daily_date"
      t.index :sku, name: "idx_raw_ozon_sales_funnel_daily_sku"
    end

    drop_table :raw_wb_analytics_sales_funnels do |t|
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
      t.decimal :avg_price, precision: 10, scale: 2
      t.decimal :avg_orders_per_day, precision: 10, scale: 2
      t.decimal :share_order_percent, precision: 10, scale: 2
      t.bigint :add_to_wishlist, default: 0
      t.decimal :localization_percent, precision: 10, scale: 2
      t.decimal :buyout_percent, precision: 10, scale: 2
      t.integer :time_to_ready_days
      t.integer :time_to_ready_hours
      t.integer :time_to_ready_mins
      t.index [:account_id, :stat_date, :nm_id], unique: true
    end

    drop_table :raw_ozon_analytics do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.date :date_from, null: false
      t.date :date_to, null: false
      t.text :dimension_keys, array: true, default: []
      t.jsonb :dimension_values
      t.integer :ordered_units
      t.decimal :revenue, precision: 18, scale: 2
      t.integer :returns_count
      t.integer :cancellations
      t.integer :hits_view_pdp
      t.integer :hits_tocart
      t.integer :session_view
      t.integer :adv_view_all
      t.jsonb :raw_json, null: false
      t.datetime :synced_at
      t.index [:account_id, :date_from, :date_to]
    end
  end
end
