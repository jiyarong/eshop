class AddCargoTypeToEcPallets < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_pallets, :cargo_type, :string, null: false, default: "pallet"
  end
end
