class AddWbLogisticsOverrideToEcSkuProfitVersionContexts < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_sku_profit_version_contexts, :wb_logistics_override_cny, :decimal, precision: 20, scale: 8
  end
end
