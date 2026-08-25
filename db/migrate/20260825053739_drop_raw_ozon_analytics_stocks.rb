class DropRawOzonAnalyticsStocks < ActiveRecord::Migration[8.1]
  def change
    drop_table :raw_ozon_analytics_stocks do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint :ozon_sku
      t.string :item_code
      t.string :item_name
      t.string :warehouse_name
      t.integer :present, default: 0
      t.integer :reserved, default: 0
      t.jsonb :raw_json, null: false
      t.datetime :synced_at
      t.index %i[account_id ozon_sku]
    end
  end
end
