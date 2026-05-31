class AddProductNameRuToEcSkus < ActiveRecord::Migration[8.0]
  def change
    add_column :ec_skus, :product_name_ru, :string
  end
end
