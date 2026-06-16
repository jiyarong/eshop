class RenameRawOzonProductAttributesAttributes < ActiveRecord::Migration[8.0]
  def change
    rename_column :raw_ozon_product_attributes, :attributes, :product_attributes
  end
end
