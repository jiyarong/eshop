class CreateRawWbSearchReportProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_wb_search_report_products do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.date :period_from, null: false
      t.date :period_to, null: false
      t.bigint :nm_id, null: false
      t.string :vendor_code
      t.string :product_name
      t.string :subject_name
      t.string :brand_name
      t.string :main_photo
      t.boolean :is_advertised
      t.boolean :is_substituted_sku
      t.boolean :is_card_rated
      t.decimal :rating, precision: 12, scale: 4
      t.decimal :feedback_rating, precision: 12, scale: 4
      t.decimal :price_min, precision: 18, scale: 4
      t.decimal :price_max, precision: 18, scale: 4
      t.decimal :avg_position, precision: 18, scale: 4
      t.decimal :avg_position_dynamics, precision: 18, scale: 4
      t.integer :open_card
      t.decimal :open_card_dynamics, precision: 18, scale: 4
      t.integer :add_to_cart
      t.decimal :add_to_cart_dynamics, precision: 18, scale: 4
      t.decimal :open_to_cart, precision: 18, scale: 4
      t.decimal :open_to_cart_dynamics, precision: 18, scale: 4
      t.integer :orders
      t.decimal :orders_dynamics, precision: 18, scale: 4
      t.decimal :cart_to_order, precision: 18, scale: 4
      t.decimal :cart_to_order_dynamics, precision: 18, scale: 4
      t.decimal :visibility, precision: 18, scale: 4
      t.decimal :visibility_dynamics, precision: 18, scale: 4
      t.string :currency
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps
    end

    add_index :raw_wb_search_report_products,
      [ :account_id, :period_from, :period_to, :nm_id ],
      unique: true,
      name: :idx_raw_wb_search_report_products_unique
    add_index :raw_wb_search_report_products,
      [ :account_id, :period_from, :period_to ],
      name: :idx_raw_wb_search_report_products_period
  end
end
