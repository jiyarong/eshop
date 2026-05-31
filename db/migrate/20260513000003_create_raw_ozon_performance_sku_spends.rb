class CreateRawOzonPerformanceSkuSpends < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_performance_sku_spends do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }

      t.date    :period_from,  null: false
      t.date    :period_to,    null: false

      # 'ppc' = PayPerClick  /  'promotion' = SEARCH_PROMO
      t.string  :ad_type,      null: false

      # PPC 行填入来源 campaign_id；Promotion 行为 null
      t.string  :campaign_id

      t.bigint  :ozon_sku_id,  null: false

      # 总支出（PPC: = spend；Promotion: combo_spend + cpo_spend）
      t.decimal :spend,        precision: 15, scale: 2, null: false

      # Promotion 明细（PPC 行为 null）
      t.decimal :combo_spend,  precision: 15, scale: 2
      t.decimal :cpo_spend,    precision: 15, scale: 2

      t.datetime :synced_at,   null: false
    end

    # 按账号+周期+类型批量查询（delete-then-insert 主路径）
    add_index :raw_ozon_performance_sku_spends,
              [:account_id, :period_from, :period_to, :ad_type],
              name: 'idx_ozon_perf_sku_spends_period'

    # 按 SKU 聚合广告支出
    add_index :raw_ozon_performance_sku_spends,
              [:account_id, :ozon_sku_id],
              name: 'idx_ozon_perf_sku_spends_sku'
  end
end
