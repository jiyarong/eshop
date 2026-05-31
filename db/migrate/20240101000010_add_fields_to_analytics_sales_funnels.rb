class AddFieldsToAnalyticsSalesFunnels < ActiveRecord::Migration[8.0]
  def change
    add_column :raw_wb_analytics_sales_funnels, :avg_price, :decimal, precision: 10, scale: 2
    add_column :raw_wb_analytics_sales_funnels, :avg_orders_per_day, :decimal, precision: 10, scale: 2
    add_column :raw_wb_analytics_sales_funnels, :share_order_percent, :decimal, precision: 10, scale: 2
    add_column :raw_wb_analytics_sales_funnels, :add_to_wishlist, :bigint, default: 0
    add_column :raw_wb_analytics_sales_funnels, :localization_percent, :decimal, precision: 10, scale: 2
    add_column :raw_wb_analytics_sales_funnels, :buyout_percent, :decimal, precision: 10, scale: 2
    add_column :raw_wb_analytics_sales_funnels, :time_to_ready_days, :integer
    add_column :raw_wb_analytics_sales_funnels, :time_to_ready_hours, :integer
    add_column :raw_wb_analytics_sales_funnels, :time_to_ready_mins, :integer
  end
end