class AddRemainingApiFieldsToRawWbStatsOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_wb_stats_orders, :finished_price, :decimal, precision: 15, scale: 2
    add_column :raw_wb_stats_orders, :income_id, :bigint
    add_column :raw_wb_stats_orders, :is_realization, :boolean
    add_column :raw_wb_stats_orders, :is_supply, :boolean
    add_column :raw_wb_stats_orders, :price_with_disc, :decimal, precision: 15, scale: 2
    add_column :raw_wb_stats_orders, :spp, :decimal, precision: 10, scale: 2
    add_column :raw_wb_stats_orders, :sticker, :string
  end
end
