class AddGNumberAndSkus < ActiveRecord::Migration[8.0]
  def change
    add_column :raw_wb_orders, :g_number, :string, limit: 200
    add_index  :raw_wb_orders, :g_number

    add_column :raw_wb_product_skus, :skus, :string, array: true, default: []
  end
end
