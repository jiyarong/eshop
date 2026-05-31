class CreateRawOzonAnalytics < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_analytics do |t|
      t.references :account,       null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.date    :date_from,        null: false
      t.date    :date_to,          null: false
      t.text    :dimension_keys,   array: true, default: []
      t.jsonb   :dimension_values
      t.integer :ordered_units
      t.decimal :revenue,          precision: 18, scale: 2
      t.integer :returns_count
      t.integer :cancellations
      t.integer :hits_view_pdp
      t.integer :hits_tocart
      t.integer :session_view
      t.integer :adv_view_all
      t.jsonb   :raw_json,         null: false
      t.datetime :synced_at
      t.index [:account_id, :date_from, :date_to]
    end

    create_table :raw_ozon_analytics_stocks do |t|
      t.references :account,       null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint  :ozon_sku
      t.string  :item_code
      t.string  :item_name
      t.string  :warehouse_name
      t.integer :present,          default: 0
      t.integer :reserved,         default: 0
      t.jsonb   :raw_json,         null: false
      t.datetime :synced_at
      t.index [:account_id, :ozon_sku]
    end
  end
end
