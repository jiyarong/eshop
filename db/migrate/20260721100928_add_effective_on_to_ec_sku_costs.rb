class AddEffectiveOnToEcSkuCosts < ActiveRecord::Migration[8.1]
  def up
    add_column :ec_sku_costs, :effective_on, :date, if_not_exists: true

    execute "UPDATE ec_sku_costs SET effective_on = DATE '2025-01-01' WHERE effective_on IS NULL"
    change_column_null :ec_sku_costs, :effective_on, false
    remove_index :ec_sku_costs, name: "idx_ec_sku_costs_sku_code", if_exists: true
    add_index :ec_sku_costs, [ :sku_code, :effective_on ], unique: true, name: "idx_ec_sku_costs_sku_code_effective_on", if_not_exists: true
    add_index :ec_sku_costs, [ :sku_code, :effective_on, :id ], name: "idx_ec_sku_costs_effective_lookup", if_not_exists: true
  end

  def down
    remove_index :ec_sku_costs, name: "idx_ec_sku_costs_effective_lookup", if_exists: true
    remove_index :ec_sku_costs, name: "idx_ec_sku_costs_sku_code_effective_on", if_exists: true
    add_index :ec_sku_costs, :sku_code, unique: true, name: "idx_ec_sku_costs_sku_code", if_not_exists: true
    remove_column :ec_sku_costs, :effective_on, if_exists: true
  end
end
