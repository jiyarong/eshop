class CreateRawWbAdSkuSpends < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_ad_sku_spends do |t|
      t.bigint  :campaign_id, null: false
      t.bigint  :nm_id,       null: false
      t.date    :stat_date,   null: false
      t.decimal :spend,       precision: 15, scale: 4, default: 0

      t.datetime :synced_at
      t.timestamps
    end

    add_index :raw_wb_ad_sku_spends, [:campaign_id, :nm_id, :stat_date],
              unique: true, name: 'idx_raw_wb_ad_sku_spends_unique'
    add_index :raw_wb_ad_sku_spends, [:nm_id, :stat_date]
  end
end
