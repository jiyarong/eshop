class CreateEcSkuProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_sku_products do |t|
      t.string :sku_code, null: false
      t.references :store, null: false, foreign_key: { to_table: :ec_stores }
      t.string :platform, null: false
      t.string :product_id, null: false
      t.string :offer_id
      t.string :platform_sku_id
      t.string :product_name

      t.timestamps
    end

    add_index :ec_sku_products, [:store_id, :product_id], unique: true, name: "idx_ec_sku_products_unique_store_product"
    add_index :ec_sku_products, [:sku_code, :store_id], name: "idx_ec_sku_products_sku_store"
    add_foreign_key :ec_sku_products, :ec_skus, column: :sku_code, primary_key: :sku_code
  end
end
