class AddRawJsonToRawWbProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_wb_products, :raw_json, :jsonb, null: false, default: {}
  end
end
