# How a scenario's logistics cost is decided: "formula" (the fixed formula: WB base rate x coefficient and a
# flat 50 RUB return, Ozon the route tariff average of the SKU's volume) or "actual" (the typed or applied
# real figures). Existing scenarios that carry typed logistics figures stay "actual", so no result changes.
class AddLogisticsModeToEcSkuProfitVersionContexts < ActiveRecord::Migration[8.1]
  def up
    add_column :ec_sku_profit_version_contexts, :logistics_mode, :string, null: false, default: "formula"
    execute <<~SQL.squish
      UPDATE ec_sku_profit_version_contexts SET logistics_mode = 'actual'
      WHERE outbound_logistics_rub IS NOT NULL OR return_logistics_rub IS NOT NULL OR wb_logistics_override_cny IS NOT NULL
    SQL
  end

  def down
    remove_column :ec_sku_profit_version_contexts, :logistics_mode
  end
end
