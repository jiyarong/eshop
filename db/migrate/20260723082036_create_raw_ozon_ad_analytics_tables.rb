class CreateRawOzonAdAnalyticsTables < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_ozon_ad_units do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string :external_id, null: false
      t.string :unit_type, null: false
      t.string :title
      t.string :state
      t.string :billing_model
      t.string :strategy
      t.string :placement, array: true, default: []
      t.decimal :daily_budget, precision: 18, scale: 2
      t.decimal :weekly_budget, precision: 18, scale: 2
      t.date :from_date
      t.date :to_date
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps
    end
    add_index :raw_ozon_ad_units, [:account_id, :unit_type, :external_id],
      unique: true, name: "idx_raw_ozon_ad_units_identity"
    add_index :raw_ozon_ad_units, [:account_id, :state]

    create_table :raw_ozon_ad_unit_products do |t|
      t.references :ad_unit, null: false, foreign_key: { to_table: :raw_ozon_ad_units }
      t.string :ozon_sku_id, null: false
      t.bigint :raw_ozon_product_id
      t.string :title
      t.string :state
      t.boolean :is_current, null: false, default: true
      t.decimal :bid, precision: 18, scale: 4
      t.decimal :bid_price, precision: 18, scale: 2
      t.decimal :target_cir, precision: 12, scale: 6
      t.decimal :price, precision: 18, scale: 2
      t.bigint :views
      t.string :source_sku
      t.string :image_url
      t.datetime :added_at
      t.datetime :removed_at
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps
    end
    add_index :raw_ozon_ad_unit_products, [:ad_unit_id, :ozon_sku_id],
      unique: true, name: "idx_raw_ozon_ad_unit_products_identity"
    add_index :raw_ozon_ad_unit_products, :raw_ozon_product_id
    add_index :raw_ozon_ad_unit_products, [:ozon_sku_id, :is_current]

    create_table :raw_ozon_ad_daily_stats do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.references :ad_unit, null: false, foreign_key: { to_table: :raw_ozon_ad_units }
      t.date :stat_date, null: false
      t.string :cost_model, null: false
      t.bigint :impressions
      t.bigint :clicks
      t.bigint :cart_additions
      t.bigint :orders_count
      t.bigint :model_orders_count
      t.decimal :ad_revenue, precision: 18, scale: 2
      t.decimal :model_revenue, precision: 18, scale: 2
      t.decimal :total_order_revenue, precision: 18, scale: 2
      t.decimal :spend, precision: 18, scale: 2
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps
    end
    add_index :raw_ozon_ad_daily_stats, [:ad_unit_id, :stat_date, :cost_model],
      unique: true, name: "idx_raw_ozon_ad_daily_stats_identity"
    add_index :raw_ozon_ad_daily_stats, [:account_id, :stat_date]

    create_table :raw_ozon_ad_sku_daily_stats do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.references :ad_unit, null: false, foreign_key: { to_table: :raw_ozon_ad_units }
      t.string :ozon_sku_id, null: false
      t.bigint :raw_ozon_product_id
      t.date :stat_date, null: false
      t.string :cost_model, null: false
      t.bigint :impressions
      t.bigint :clicks
      t.bigint :cart_additions
      t.bigint :orders_count
      t.bigint :model_orders_count
      t.decimal :ad_revenue, precision: 18, scale: 2
      t.decimal :model_revenue, precision: 18, scale: 2
      t.decimal :total_order_revenue, precision: 18, scale: 2
      t.decimal :spend, precision: 18, scale: 2
      t.decimal :price, precision: 18, scale: 2
      t.decimal :avg_cpc, precision: 18, scale: 4
      t.decimal :ctr, precision: 12, scale: 6
      t.decimal :drr, precision: 12, scale: 6
      t.datetime :date_added
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps
    end
    add_index :raw_ozon_ad_sku_daily_stats,
      [:ad_unit_id, :ozon_sku_id, :stat_date, :cost_model],
      unique: true, name: "idx_raw_ozon_ad_sku_daily_stats_identity"
    add_index :raw_ozon_ad_sku_daily_stats, [:account_id, :stat_date]
    add_index :raw_ozon_ad_sku_daily_stats, :raw_ozon_product_id

    create_table :raw_ozon_ad_report_runs do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string :report_type, null: false
      t.string :endpoint, null: false
      t.date :period_from, null: false
      t.date :period_to, null: false
      t.string :external_uuid
      t.string :state, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.jsonb :request_body, null: false, default: {}
      t.string :response_checksum
      t.text :error_message
      t.datetime :submitted_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :raw_ozon_ad_report_runs,
      [:account_id, :report_type, :period_from, :period_to],
      name: "idx_raw_ozon_ad_report_runs_lookup"
    add_index :raw_ozon_ad_report_runs, [:account_id, :state]
  end
end
