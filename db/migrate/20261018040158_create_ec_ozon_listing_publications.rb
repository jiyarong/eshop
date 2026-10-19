class CreateEcOzonListingPublications < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_ozon_listing_publications do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.references :store, null: false, foreign_key: { to_table: :ec_stores }
      t.string :sku_code, null: false
      t.string :operation, null: false, default: "import"
      t.string :offer_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :payload_checksum, null: false
      t.string :state, null: false, default: "draft"
      t.datetime :confirmed_at
      t.string :ozon_task_id
      t.integer :attempts, null: false, default: 0
      t.string :request_id
      t.jsonb :error_details, null: false, default: []
      t.jsonb :response_json, null: false, default: {}
      t.jsonb :final_image_urls, null: false, default: []
      t.string :product_id
      t.string :platform_sku_id
      t.text :last_error
      t.datetime :submitted_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :ec_ozon_listing_publications,
      [:account_id, :offer_id, :operation, :payload_checksum],
      unique: true,
      name: "idx_ozon_listing_publications_idempotency"
    add_index :ec_ozon_listing_publications, [:account_id, :ozon_task_id]
    add_index :ec_ozon_listing_publications, [:store_id, :sku_code]
    add_foreign_key :ec_ozon_listing_publications, :ec_skus,
      column: :sku_code, primary_key: :sku_code
  end
end
