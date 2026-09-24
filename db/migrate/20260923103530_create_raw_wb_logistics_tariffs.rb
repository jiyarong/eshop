class CreateRawWbLogisticsTariffs < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_wb_logistics_tariffs do |t|
      t.references :snapshot, null: false, foreign_key: { to_table: :raw_wb_logistics_tariff_snapshots }
      t.string :delivery_mode, null: false
      t.string :warehouse_name, null: false
      t.string :geo_name
      t.decimal :base_rub, precision: 12, scale: 4, null: false
      t.decimal :logistics_coeff, precision: 10, scale: 6, null: false
      t.decimal :coefficient_percent, precision: 10, scale: 4, null: false
      t.decimal :liter_rub, precision: 12, scale: 4, null: false

      t.timestamps
    end

    add_index :raw_wb_logistics_tariffs,
      [ :snapshot_id, :delivery_mode, :warehouse_name, :geo_name ],
      unique: true, name: "idx_raw_wb_logistics_tariffs_unique"
    add_index :raw_wb_logistics_tariffs, [ :snapshot_id, :delivery_mode ],
      name: "idx_raw_wb_logistics_tariffs_snapshot_mode"
  end
end
