class AddFormulaParametersToEcSkuProfitVersionContexts < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_sku_profit_version_contexts, :ozon_operation_rate, :decimal, precision: 14, scale: 10
    add_column :ec_sku_profit_version_contexts, :ozon_warehouse_rate, :decimal, precision: 14, scale: 10
    add_column :ec_sku_profit_version_contexts, :ozon_import_vat_cost_rate, :decimal, precision: 14, scale: 10
    add_column :ec_sku_profit_version_contexts, :advertising_fixed_rub, :decimal, precision: 20, scale: 8
  end
end
