class AddMissingMetricsToRawOzonSalesFunnels < ActiveRecord::Migration[8.1]
  def change
    %i[raw_ozon_sales_funnel_daily raw_ozon_sales_funnel_period].each do |table|
      add_column table, :conv_tocart_search, :decimal, precision: 10, scale: 4
      add_column table, :conv_tocart_pdp, :decimal, precision: 10, scale: 4
      add_column table, :delivered_units, :bigint, default: 0
      add_column table, :position_category, :decimal, precision: 12, scale: 4
    end
  end
end
