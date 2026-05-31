class CreateRawOzonPerformanceTables < ActiveRecord::Migration[8.0]
  def change
    # 广告活动
    create_table :raw_ozon_performance_campaigns do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string  :campaign_id,    null: false
      t.string  :title
      t.string  :state                                   # RUNNING / INACTIVE / ARCHIVED
      t.string  :adv_object_type                         # SKU / SEARCH_PROMO
      t.string  :payment_type                            # CPC / CPO
      t.string  :placement,      array: true, default: []
      t.date    :from_date
      t.date    :to_date
      t.decimal :daily_budget,   precision: 15, scale: 2
      t.decimal :weekly_budget,  precision: 15, scale: 2
      t.jsonb   :raw_json
      t.datetime :synced_at
      t.timestamps
    end
    add_index :raw_ozon_performance_campaigns, [:account_id, :campaign_id],
              unique: true, name: "idx_ozon_perf_campaigns_unique"

    # 活动内的 SKU（campaign → ozon_sku 多对多）
    create_table :raw_ozon_performance_campaign_skus do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :raw_ozon_performance_campaigns }
      t.string  :ozon_sku_id, null: false                # 对应 raw_ozon_products.ozon_sku
      t.timestamps
    end
    add_index :raw_ozon_performance_campaign_skus, [:campaign_id, :ozon_sku_id],
              unique: true, name: "idx_ozon_perf_campaign_skus_unique"

    # 广告每日统计（来自 /api/client/statistics/daily）
    create_table :raw_ozon_performance_daily_stats do |t|
      t.references :account,  null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.references :campaign, null: false, foreign_key: { to_table: :raw_ozon_performance_campaigns }
      t.date    :stat_date,      null: false
      t.integer :impressions,    default: 0              # 曝光量
      t.integer :clicks,         default: 0              # 点击量
      t.decimal :spend,          precision: 15, scale: 2, default: 0  # 广告花费（卢布）
      t.integer :orders_count,   default: 0              # 广告带来的订单数
      t.decimal :orders_revenue, precision: 15, scale: 2, default: 0  # 广告带来的订单金额
      t.datetime :synced_at
      t.timestamps
    end
    add_index :raw_ozon_performance_daily_stats, [:campaign_id, :stat_date],
              unique: true, name: "idx_ozon_perf_daily_stats_unique"
    add_index :raw_ozon_performance_daily_stats, [:account_id, :stat_date],
              name: "idx_ozon_perf_daily_stats_account_date"
  end
end
