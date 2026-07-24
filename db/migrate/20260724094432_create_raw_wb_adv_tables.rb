class CreateRawWbAdvTables < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_wb_adv_campaigns do |t|
      t.references :store, null: false, foreign_key: { to_table: :ec_stores }
      t.bigint :advert_id, null: false
      t.integer :campaign_type
      t.integer :status
      t.string :name
      t.string :payment_type
      t.string :bid_type
      t.string :currency
      t.jsonb :placements, null: false, default: {}
      t.boolean :can_change_nms
      t.datetime :source_created_at
      t.datetime :source_deleted_at
      t.datetime :source_started_at
      t.datetime :source_updated_at
      t.boolean :is_current, null: false, default: true
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps

      t.index [:store_id, :advert_id], unique: true, name: "idx_wb_adv_campaigns_store_advert"
      t.index [:store_id, :status], name: "idx_wb_adv_campaigns_store_status"
    end

    create_table :raw_wb_adv_campaign_products do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :raw_wb_adv_campaigns }
      t.bigint :nm_id, null: false
      t.bigint :subject_id
      t.string :subject_name
      t.bigint :search_bid_kopecks
      t.bigint :recommendation_bid_kopecks
      t.boolean :is_current, null: false, default: true
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps

      t.index [:campaign_id, :nm_id], unique: true, name: "idx_wb_adv_campaign_products_unique"
      t.index :nm_id
    end

    create_table :raw_wb_adv_budget_snapshots do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :raw_wb_adv_campaigns }
      t.decimal :cash, precision: 15, scale: 2, null: false, default: 0
      t.decimal :netting, precision: 15, scale: 2, null: false, default: 0
      t.decimal :total, precision: 15, scale: 2, null: false, default: 0
      t.string :currency
      t.datetime :observed_at, null: false
      t.jsonb :raw_payload, null: false, default: {}
      t.timestamps

      t.index [:campaign_id, :observed_at], name: "idx_wb_adv_budgets_campaign_observed"
    end

    create_table :raw_wb_adv_campaign_daily_stats do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :raw_wb_adv_campaigns }
      t.date :stat_date, null: false
      t.bigint :views, null: false, default: 0
      t.bigint :clicks, null: false, default: 0
      t.bigint :add_to_cart, null: false, default: 0
      t.bigint :orders, null: false, default: 0
      t.bigint :ordered_units, null: false, default: 0
      t.bigint :canceled, null: false, default: 0
      t.decimal :spend, precision: 15, scale: 4, null: false, default: 0
      t.decimal :revenue, precision: 15, scale: 2, null: false, default: 0
      t.decimal :ctr, precision: 12, scale: 4
      t.decimal :cpc, precision: 15, scale: 4
      t.decimal :cr, precision: 12, scale: 4
      t.string :currency
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps

      t.index [:campaign_id, :stat_date], unique: true, name: "idx_wb_adv_campaign_daily_unique"
      t.index :stat_date
    end

    create_table :raw_wb_adv_product_daily_stats do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :raw_wb_adv_campaigns }
      t.date :stat_date, null: false
      t.integer :app_type, null: false, default: 0
      t.bigint :nm_id, null: false
      t.string :product_name
      t.bigint :views, null: false, default: 0
      t.bigint :clicks, null: false, default: 0
      t.bigint :add_to_cart, null: false, default: 0
      t.bigint :orders, null: false, default: 0
      t.bigint :ordered_units, null: false, default: 0
      t.bigint :canceled, null: false, default: 0
      t.decimal :spend, precision: 15, scale: 4, null: false, default: 0
      t.decimal :revenue, precision: 15, scale: 2, null: false, default: 0
      t.decimal :ctr, precision: 12, scale: 4
      t.decimal :cpc, precision: 15, scale: 4
      t.decimal :cr, precision: 12, scale: 4
      t.decimal :avg_position, precision: 12, scale: 4
      t.string :currency
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps

      t.index [:campaign_id, :stat_date, :app_type, :nm_id], unique: true,
        name: "idx_wb_adv_product_daily_unique"
      t.index [:nm_id, :stat_date], name: "idx_wb_adv_product_daily_nm_date"
    end

    create_table :raw_wb_adv_expenses do |t|
      t.references :store, null: false, foreign_key: { to_table: :ec_stores }
      t.references :campaign, foreign_key: { to_table: :raw_wb_adv_campaigns }
      t.bigint :advert_id, null: false
      t.datetime :expense_at, null: false
      t.string :campaign_name
      t.string :payment_type
      t.integer :upd_num
      t.decimal :amount, precision: 15, scale: 4, null: false, default: 0
      t.integer :advert_type
      t.integer :advert_status
      t.string :currency
      t.string :source_fingerprint, null: false
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps

      t.index [:store_id, :source_fingerprint], unique: true, name: "idx_wb_adv_expenses_fingerprint"
      t.index [:store_id, :expense_at], name: "idx_wb_adv_expenses_store_date"
      t.index [:advert_id, :expense_at], name: "idx_wb_adv_expenses_advert_date"
    end
  end
end
