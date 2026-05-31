class AddWbReturnRatesToSkuPlatformCosts < ActiveRecord::Migration[8.0]
  def change
    add_column :ec_sku_platform_costs, :wb_return_rate,       :decimal, precision: 8, scale: 6
    add_column :ec_sku_platform_costs, :wb_fixed_return_rate, :decimal, precision: 8, scale: 6
  end
end
