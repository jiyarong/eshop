class CreateRawOzonSalesFunnelPeriod < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_ozon_sales_funnel_period do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.date :period_start, null: false
      t.date :period_end, null: false

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

      t.index [:account_id, :period_start, :period_end, :sku],
        unique: true,
        name: "idx_raw_ozon_sales_funnel_period_unique"
      t.index [:period_start, :period_end], name: "idx_raw_ozon_sales_funnel_period_dates"
      t.index [:sku], name: "idx_raw_ozon_sales_funnel_period_sku"
    end
  end
end
