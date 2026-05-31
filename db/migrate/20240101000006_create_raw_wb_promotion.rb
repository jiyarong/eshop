class CreateRawWbPromotion < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_ad_campaigns do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.bigint :wb_advert_id, index: { unique: true }
      t.string :name
      t.integer :campaign_type
      t.integer :status
      t.decimal :daily_budget, precision: 15, scale: 2
      t.decimal :total_budget, precision: 15, scale: 2
      t.datetime :start_time
      t.datetime :end_time
      t.datetime :synced_at
      t.timestamps
    end

    create_table :raw_wb_ad_campaign_products, id: false do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :raw_wb_ad_campaigns }
      t.bigint :nm_id, null: false
      t.decimal :bid, precision: 10, scale: 2
      t.index [:campaign_id, :nm_id], unique: true
    end

    create_table :raw_wb_ad_keyword_bids do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :raw_wb_ad_campaigns }
      t.string :keyword
      t.decimal :bid, precision: 10, scale: 2
      t.boolean :is_active, default: true
    end

    create_table :raw_wb_ad_negative_keywords do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :raw_wb_ad_campaigns }
      t.string :keyword
    end

    create_table :raw_wb_ad_daily_stats do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :raw_wb_ad_campaigns }
      t.date :stat_date
      t.bigint :views, default: 0
      t.bigint :clicks, default: 0
      t.decimal :ctr, precision: 10, scale: 4
      t.decimal :cpc, precision: 10, scale: 2
      t.decimal :spend, precision: 15, scale: 2
      t.bigint :add_to_cart, default: 0
      t.bigint :orders, default: 0
      t.decimal :cr, precision: 10, scale: 4
      t.decimal :revenue, precision: 15, scale: 2
      t.index [:campaign_id, :stat_date], unique: true
    end

    create_table :raw_wb_promotions do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.bigint :wb_promotion_id, index: { unique: true }
      t.string :name
      t.datetime :period_start
      t.datetime :period_end
      t.integer :discount
      t.datetime :synced_at
    end

    create_table :raw_wb_promotion_products, id: false do |t|
      t.references :promotion, null: false, foreign_key: { to_table: :raw_wb_promotions }
      t.bigint :nm_id, null: false
      t.integer :discount
      t.index [:promotion_id, :nm_id], unique: true
    end
  end
end
