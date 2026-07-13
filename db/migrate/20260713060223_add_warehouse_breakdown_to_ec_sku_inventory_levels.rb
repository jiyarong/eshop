class AddWarehouseBreakdownToEcSkuInventoryLevels < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_sku_inventory_levels, :warehouse_breakdown, :jsonb, default: [], null: false
  end
end
