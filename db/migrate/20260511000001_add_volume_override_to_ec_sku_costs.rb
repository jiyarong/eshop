class AddVolumeOverrideToEcSkuCosts < ActiveRecord::Migration[8.0]
  def change
    add_column :ec_sku_costs, :pkg_volume_override_l, :decimal, precision: 8, scale: 4
  end
end
