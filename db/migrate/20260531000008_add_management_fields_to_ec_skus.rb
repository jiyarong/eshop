class AddManagementFieldsToEcSkus < ActiveRecord::Migration[8.0]
  def change
    add_reference :ec_skus, :sku_category, foreign_key: { to_table: :ec_sku_categories }
    add_column :ec_skus, :color, :string
    add_column :ec_skus, :spec, :string
    add_column :ec_skus, :size, :string
    add_column :ec_skus, :weight_kg, :decimal, precision: 10, scale: 4
    add_column :ec_skus, :volume_l, :decimal, precision: 10, scale: 4
    add_column :ec_skus, :model, :string
    add_column :ec_skus, :quality_grade, :string
    add_column :ec_skus, :features, :text
  end
end
