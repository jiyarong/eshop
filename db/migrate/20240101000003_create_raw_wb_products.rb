class CreateRawWbProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_products do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.bigint :nm_id, index: { unique: true }
      t.bigint :imt_id
      t.string :vendor_code, null: false
      t.string :brand
      t.string :title
      t.text :description
      t.references :subject, foreign_key: { to_table: :raw_wb_subjects }
      t.string :subject_name
      t.string :wb_category
      t.boolean :is_in_trash, default: false
      t.datetime :synced_at
      t.timestamps
    end

    create_table :raw_wb_product_characteristics do |t|
      t.references :product, null: false, foreign_key: { to_table: :raw_wb_products }
      t.integer :charc_id
      t.string :charc_name
      t.jsonb :value
    end

    create_table :raw_wb_product_skus do |t|
      t.references :product, null: false, foreign_key: { to_table: :raw_wb_products }
      t.bigint :chrt_id, index: { unique: true }
      t.string :tech_size
      t.string :wb_size
      t.string :barcode
      t.timestamps
    end

    create_table :raw_wb_product_media do |t|
      t.references :product, null: false, foreign_key: { to_table: :raw_wb_products }
      t.string :media_type
      t.text :url
      t.integer :position
      t.timestamps
    end

    create_table :raw_wb_product_tags do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.integer :wb_tag_id
      t.string :name
      t.string :color
    end

    create_table :raw_wb_product_tag_links, id: false do |t|
      t.references :product, null: false, foreign_key: { to_table: :raw_wb_products }
      t.references :tag, null: false, foreign_key: { to_table: :raw_wb_product_tags }
      t.index [:product_id, :tag_id], unique: true
    end
  end
end
