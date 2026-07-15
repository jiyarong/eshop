class AddLocationFieldsToRawWbStatsOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_wb_stats_orders, :country_name, :string
    add_column :raw_wb_stats_orders, :oblast_okrug_name, :string
    add_column :raw_wb_stats_orders, :region_name, :string
  end
end
