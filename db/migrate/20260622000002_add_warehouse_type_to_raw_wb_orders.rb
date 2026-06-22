class AddWarehouseTypeToRawWbOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :raw_wb_orders, :warehouse_type, :string
    add_column :raw_wb_stats_orders, :warehouse_type, :string
  end
end
