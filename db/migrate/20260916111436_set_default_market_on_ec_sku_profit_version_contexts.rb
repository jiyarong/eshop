class SetDefaultMarketOnEcSkuProfitVersionContexts < ActiveRecord::Migration[8.1]
  def up
    change_column_default :ec_sku_profit_version_contexts, :market, from: "RU", to: "ru"
  end

  def down
    change_column_default :ec_sku_profit_version_contexts, :market, from: "ru", to: "RU"
  end
end
