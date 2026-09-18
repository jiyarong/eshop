class CreateRawWbCommissionTariffs < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_wb_commission_tariffs do |t|
      t.references :snapshot, null: false, foreign_key: { to_table: :raw_wb_commission_tariff_snapshots }
      t.bigint :wb_subject_id, null: false
      t.bigint :wb_parent_id
      t.string :parent_name
      t.string :subject_name
      t.decimal :kgvp_booking, precision: 8, scale: 4
      t.decimal :kgvp_marketplace, precision: 8, scale: 4
      t.decimal :kgvp_pickup, precision: 8, scale: 4
      t.decimal :kgvp_supplier, precision: 8, scale: 4
      t.decimal :kgvp_supplier_express, precision: 8, scale: 4
      t.decimal :paid_storage_kgvp, precision: 8, scale: 4
      t.timestamps
    end

    add_index :raw_wb_commission_tariffs, [ :snapshot_id, :wb_subject_id ],
      unique: true, name: "idx_raw_wb_commission_tariffs_unique"
    add_index :raw_wb_commission_tariffs, :wb_subject_id,
      name: "idx_raw_wb_commission_tariffs_subject"
  end
end
