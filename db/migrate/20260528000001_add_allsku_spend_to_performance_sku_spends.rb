class AddAllskuSpendToPerformanceSkuSpends < ActiveRecord::Migration[8.0]
  def change
    add_column :raw_ozon_performance_sku_spends, :allsku_spend, :decimal, precision: 15, scale: 2
  end
end
