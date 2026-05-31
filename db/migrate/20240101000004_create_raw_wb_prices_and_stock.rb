class CreateRawWbPricesAndStock < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_product_prices do |t|
      t.references :product, null: false, foreign_key: { to_table: :raw_wb_products }
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.decimal :price, precision: 15, scale: 2
      t.integer :discount
      t.integer :club_discount
      t.decimal :final_price, precision: 15, scale: 2
      t.boolean :is_in_quarantine, default: false
      t.timestamps
    end

    create_table :raw_wb_product_price_histories do |t|
      t.references :product, null: false, foreign_key: { to_table: :raw_wb_products }
      t.decimal :price, precision: 15, scale: 2
      t.integer :discount
      t.integer :club_discount
      t.datetime :changed_at, default: -> { 'CURRENT_TIMESTAMP' }
    end

    create_table :raw_wb_warehouses do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.bigint :wb_warehouse_id, index: { unique: true }
      t.string :name, null: false
      t.text :address
      t.string :work_time
      t.string :city
      t.decimal :longitude, precision: 10, scale: 7
      t.decimal :latitude, precision: 10, scale: 7
      t.string :warehouse_type
      t.boolean :is_active, default: true
      t.timestamps
    end

    create_table :raw_wb_stocks do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.references :warehouse, null: false, foreign_key: { to_table: :raw_wb_warehouses }
      t.references :sku, foreign_key: { to_table: :raw_wb_product_skus }
      t.string :barcode
      t.integer :quantity, null: false, default: 0
      t.datetime :updated_at
      t.index [:warehouse_id, :barcode], unique: true
    end

    create_table :raw_wb_stock_histories do |t|
      t.references :warehouse, null: false, foreign_key: { to_table: :raw_wb_warehouses }
      t.string :barcode
      t.integer :quantity
      t.datetime :snapshot_at, default: -> { 'CURRENT_TIMESTAMP' }
    end
  end
end
