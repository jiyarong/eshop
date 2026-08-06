class CreateEcReturnItems < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_return_items do |t|
      t.references :return, null: false, foreign_key: { to_table: :ec_returns }
      t.references :store, null: false, foreign_key: { to_table: :ec_stores }
      t.references :sku_product, foreign_key: { to_table: :ec_sku_products }
      t.references :order_item, foreign_key: { to_table: :ec_order_items }
      t.string :platform, null: false
      t.string :item_key, null: false
      t.string :platform_sku_id
      t.string :product_id
      t.string :offer_id
      t.integer :quantity, null: false, default: 1
      t.boolean :restockable, null: false, default: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ec_return_items, %i[return_id item_key], unique: true
    add_index :ec_return_items, :restockable
  end
end
