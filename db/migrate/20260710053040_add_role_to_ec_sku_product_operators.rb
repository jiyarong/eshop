class AddRoleToEcSkuProductOperators < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_sku_product_operators, :role, :string, null: false, default: "operator"
  end
end
