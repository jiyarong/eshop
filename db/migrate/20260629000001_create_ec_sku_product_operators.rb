class CreateEcSkuProductOperators < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_sku_product_operators do |t|
      t.references :sku_product, null: false, foreign_key: { to_table: :ec_sku_products }
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :ec_sku_product_operators,
      [:sku_product_id, :user_id],
      unique: true,
      name: "idx_ec_sku_product_operators_unique"
  end
end
