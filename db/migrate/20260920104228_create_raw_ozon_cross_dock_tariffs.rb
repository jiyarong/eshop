class CreateRawOzonCrossDockTariffs < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_ozon_cross_dock_tariff_snapshots do |t|
      t.string :market_code, null: false, default: "ru"
      t.date :effective_from, null: false
      t.date :effective_to
      t.string :source_file_name, null: false
      t.string :source_checksum, null: false
      t.string :source_url
      t.string :status, null: false, default: "running"
      t.boolean :is_current, null: false, default: false
      t.datetime :imported_at, null: false
      t.integer :row_count
      t.string :currency_code, null: false, default: "RUB"
      t.boolean :includes_vat, null: false, default: true
      t.text :error_message
      t.timestamps
    end

    add_index :raw_ozon_cross_dock_tariff_snapshots,
      [:market_code, :source_checksum],
      unique: true,
      name: "idx_raw_ozon_cross_dock_snapshots_source"
    add_index :raw_ozon_cross_dock_tariff_snapshots,
      :market_code,
      unique: true,
      where: "is_current",
      name: "idx_raw_ozon_cross_dock_snapshots_current"
    add_index :raw_ozon_cross_dock_tariff_snapshots,
      [:market_code, :effective_from],
      name: "idx_raw_ozon_cross_dock_snapshots_effective"

    create_table :raw_ozon_cross_dock_tariffs do |t|
      t.references :snapshot, null: false,
        foreign_key: { to_table: :raw_ozon_cross_dock_tariff_snapshots }
      t.string :supply_receiving_zone_name, null: false
      t.string :supply_receiving_zone_key, null: false
      t.string :destination_cluster_name, null: false
      t.string :destination_cluster_key, null: false
      t.decimal :pallet_rub_per_l, precision: 12, scale: 2, null: false
      t.decimal :box_rub_per_l, precision: 12, scale: 2, null: false
      t.timestamps
    end

    add_index :raw_ozon_cross_dock_tariffs,
      [:snapshot_id, :supply_receiving_zone_key, :destination_cluster_key],
      unique: true,
      name: "idx_raw_ozon_cross_dock_tariffs_identity"
    add_index :raw_ozon_cross_dock_tariffs,
      [:snapshot_id, :destination_cluster_key],
      name: "idx_raw_ozon_cross_dock_tariffs_destination"
  end
end
