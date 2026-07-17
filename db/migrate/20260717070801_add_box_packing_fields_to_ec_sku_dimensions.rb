class AddBoxPackingFieldsToEcSkuDimensions < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_sku_dimensions, :inner_box_weight_kg, :decimal, precision: 10, scale: 3
    add_column :ec_sku_dimensions, :outer_box_weight_kg, :decimal, precision: 10, scale: 3
    add_column :ec_sku_dimensions, :outer_box_pcs, :integer
  end
end
