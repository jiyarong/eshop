class AddWbLogisticsLiterRubToSkuProfitVersionContexts < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_sku_profit_version_contexts, :wb_logistics_liter_rub, :decimal, precision: 20, scale: 8
    execute <<~SQL.squish
      UPDATE ec_sku_profit_version_contexts
      SET wb_logistics_liter_rub = 14
      WHERE platform = 'wb' AND wb_logistics_liter_rub IS NULL
    SQL
  end
end
