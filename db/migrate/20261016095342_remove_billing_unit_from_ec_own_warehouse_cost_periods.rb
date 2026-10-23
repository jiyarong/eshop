class RemoveBillingUnitFromEcOwnWarehouseCostPeriods < ActiveRecord::Migration[8.1]
  def change
    remove_column :ec_own_warehouse_cost_periods, :billing_unit, :string
  end
end
