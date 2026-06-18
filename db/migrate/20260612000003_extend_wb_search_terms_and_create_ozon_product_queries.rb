class ExtendWbSearchTermsAndCreateOzonProductQueries < ActiveRecord::Migration[8.0]
  def change
    # ── 1. 扩展 raw_wb_analytics_search_terms ──────────────────────────────
    add_column :raw_wb_analytics_search_terms, :median_position,      :decimal, precision: 10, scale: 2, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :open_card,            :bigint, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :open_card_percentile, :integer, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :add_to_cart,          :bigint, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :add_to_cart_percentile, :integer, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :open_to_cart,         :decimal, precision: 10, scale: 4, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :open_to_cart_percentile, :integer, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :orders_percentile,    :integer, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :cart_to_order,        :decimal, precision: 10, scale: 4, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :cart_to_order_percentile, :integer, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :visibility,           :integer, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :week_frequency,       :bigint, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :vendor_code,          :string, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :subject_name,         :string, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :brand_name,           :string, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :product_name,         :string, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :rating,               :decimal, precision: 5, scale: 2, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :feedback_rating,      :decimal, precision: 5, scale: 2, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :price_min,            :decimal, precision: 15, scale: 2, if_not_exists: true
    add_column :raw_wb_analytics_search_terms, :price_max,            :decimal, precision: 15, scale: 2, if_not_exists: true

    # ── 2. Ozon：SKU 级搜索汇总（/v1/analytics/product-queries）─────────────
    create_table :raw_ozon_product_queries, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.date    :period_from,          null: false
      t.date    :period_to,            null: false
      t.bigint  :sku,                  null: false
      t.string  :offer_id
      t.string  :name
      t.string  :category
      t.string  :currency
      t.bigint  :unique_search_users
      t.bigint  :unique_view_users
      t.decimal :position,             precision: 10, scale: 2
      t.decimal :view_conversion,      precision: 10, scale: 4
      t.decimal :gmv,                  precision: 15, scale: 2
      t.datetime :synced_at

      t.index [:account_id, :period_from, :sku], unique: true, name: 'idx_ozon_product_queries_unique'
    end

    # ── 3. Ozon：词级搜索明细（/v1/analytics/product-queries/details）────────
    create_table :raw_ozon_product_query_details, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.date    :period_from,          null: false
      t.date    :period_to,            null: false
      t.bigint  :sku,                  null: false
      t.string  :query,                null: false
      t.integer :query_index
      t.string  :currency
      t.bigint  :unique_search_users
      t.bigint  :unique_view_users
      t.decimal :position,             precision: 10, scale: 2
      t.decimal :view_conversion,      precision: 10, scale: 4
      t.bigint  :order_count
      t.decimal :gmv,                  precision: 15, scale: 2
      t.datetime :synced_at

      t.index [:account_id, :period_from, :sku, :query], unique: true,
              name: 'idx_ozon_product_query_details_unique', length: { query: 200 }
    end
  end
end
