class RemoveSupplyTypeFromRawWbSupplies < ActiveRecord::Migration[8.1]
  def change
    remove_column :raw_wb_supplies, :supply_type, :string
  end
end
