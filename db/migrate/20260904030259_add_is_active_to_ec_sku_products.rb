class AddIsActiveToEcSkuProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_sku_products, :is_active, :boolean, null: false, default: true
    add_index :ec_sku_products, :is_active
  end
end
