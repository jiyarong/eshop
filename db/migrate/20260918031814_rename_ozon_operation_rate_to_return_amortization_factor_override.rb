class RenameOzonOperationRateToReturnAmortizationFactorOverride < ActiveRecord::Migration[8.1]
  def up
    rename_column :ec_sku_profit_version_contexts,
      :ozon_operation_rate,
      :return_amortization_factor_override

    execute <<~SQL.squish
      UPDATE ec_sku_profit_version_contexts
      SET return_rate = return_amortization_factor_override / (1 + return_amortization_factor_override),
          return_amortization_factor_override = NULL
      WHERE platform = 'ozon'
        AND return_amortization_factor_override IS NOT NULL
        AND return_amortization_factor_override >= 0
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE ec_sku_profit_version_contexts
      SET return_amortization_factor_override = COALESCE(
        return_amortization_factor_override,
        return_rate / (1 - return_rate)
      )
      WHERE platform = 'ozon'
        AND return_rate IS NOT NULL
        AND return_rate >= 0
        AND return_rate < 1
    SQL

    rename_column :ec_sku_profit_version_contexts,
      :return_amortization_factor_override,
      :ozon_operation_rate
  end
end
