class CreateRawOzonCatalog < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_categories do |t|
      t.references :account,     null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint  :category_id,    null: false
      t.bigint  :parent_id
      t.string  :title
      t.boolean :disabled,       default: false
      t.jsonb   :children
      t.jsonb   :raw_json
      t.datetime :synced_at
      t.index [:account_id, :category_id], unique: true
    end

    create_table :raw_ozon_products do |t|
      t.references :account,              null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint  :ozon_product_id,         null: false
      t.string  :offer_id
      t.string  :name
      t.bigint  :description_category_id
      t.bigint  :type_id
      t.string  :currency_code
      t.boolean :is_archived,             default: false
      t.boolean :is_autoarchived,         default: false
      t.boolean :has_discounted_fbo_item, default: false
      t.integer :discounted_fbo_stocks,   default: 0
      t.text    :barcodes,                array: true, default: []
      t.jsonb   :images
      t.jsonb   :images360
      t.jsonb   :color_image
      t.jsonb   :commissions
      t.jsonb   :availabilities
      t.jsonb   :raw_json,                null: false
      t.datetime :created_at
      t.datetime :synced_at
      t.index [:account_id, :ozon_product_id], unique: true
      t.index [:account_id, :offer_id]
    end

    create_table :raw_ozon_product_attributes do |t|
      t.references :account,      null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint  :ozon_product_id, null: false
      t.string  :offer_id
      t.jsonb   :attributes,      default: []
      t.jsonb   :complex_attributes, default: []
      t.string  :barcode
      t.jsonb   :raw_json,        null: false
      t.datetime :synced_at
      t.index [:account_id, :ozon_product_id], unique: true
    end

    create_table :raw_ozon_product_prices do |t|
      t.references :account,      null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint  :ozon_product_id, null: false
      t.string  :offer_id
      t.decimal :price,           precision: 18, scale: 2
      t.decimal :old_price,       precision: 18, scale: 2
      t.decimal :marketing_price, precision: 18, scale: 2
      t.decimal :min_price,       precision: 18, scale: 2
      t.decimal :buybox_price,    precision: 18, scale: 2
      t.string  :currency_code
      t.jsonb   :commissions
      t.boolean :is_in_discount,  default: false
      t.decimal :discount_percent, precision: 5, scale: 2
      t.integer :acquiring
      t.decimal :volume_weight,   precision: 10, scale: 3
      t.jsonb   :raw_json,        null: false
      t.datetime :synced_at
      t.index [:account_id, :ozon_product_id], unique: true
    end

    create_table :raw_ozon_product_stocks do |t|
      t.references :account,       null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint  :ozon_product_id,  null: false
      t.string  :offer_id
      t.integer :present_fbo,      default: 0
      t.integer :reserved_fbo,     default: 0
      t.integer :present_fbs,      default: 0
      t.integer :reserved_fbs,     default: 0
      t.jsonb   :stocks_by_warehouse
      t.jsonb   :raw_json,         null: false
      t.datetime :synced_at
      t.index [:account_id, :ozon_product_id], unique: true
    end
  end
end
