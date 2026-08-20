class AddProductInfoToEcSkus < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_skus, :product_info, :text
  end
end
