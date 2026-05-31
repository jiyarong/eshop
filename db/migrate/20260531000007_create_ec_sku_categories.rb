class CreateEcSkuCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_sku_categories do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.references :parent, foreign_key: { to_table: :ec_sku_categories }
      t.integer :position, null: false, default: 0
      t.boolean :is_active, null: false, default: true
      t.text :memo
      t.timestamps
    end

    add_index :ec_sku_categories, :code, unique: true
    add_index :ec_sku_categories, :name
    add_index :ec_sku_categories, :is_active
  end
end
