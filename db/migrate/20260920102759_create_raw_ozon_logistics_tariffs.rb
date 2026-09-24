class CreateRawOzonLogisticsTariffs < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_ozon_logistics_tariff_snapshots do |t|
      t.string :market_code, null: false, default: "ru"
      t.date :effective_from, null: false
      t.date :effective_to
      t.string :source_file_name, null: false
      t.string :source_checksum, null: false
      t.string :source_url
      t.string :status, null: false, default: "running"
      t.boolean :is_current, null: false, default: false
      t.datetime :imported_at, null: false
      t.integer :route_row_count
      t.integer :default_row_count
      t.string :currency_code, null: false, default: "RUB"
      t.boolean :includes_vat, null: false, default: true
      t.text :error_message
      t.timestamps
    end

    add_index :raw_ozon_logistics_tariff_snapshots,
      [:market_code, :source_checksum],
      unique: true,
      name: "idx_raw_ozon_logistics_snapshots_source"
    add_index :raw_ozon_logistics_tariff_snapshots,
      :market_code,
      unique: true,
      where: "is_current",
      name: "idx_raw_ozon_logistics_snapshots_current"
    add_index :raw_ozon_logistics_tariff_snapshots,
      [:market_code, :effective_from],
      name: "idx_raw_ozon_logistics_snapshots_effective"

    create_table :raw_ozon_logistics_tariffs do |t|
      t.references :snapshot, null: false,
        foreign_key: { to_table: :raw_ozon_logistics_tariff_snapshots }
      t.integer :volume_band_order, null: false
      t.decimal :volume_min_l, precision: 10, scale: 3, null: false
      t.decimal :volume_max_l, precision: 10, scale: 3
      t.string :volume_band_label, null: false
      t.string :origin_cluster_name, null: false
      t.string :origin_cluster_key, null: false
      t.string :destination_cluster_name, null: false
      t.string :destination_cluster_key, null: false
      t.decimal :fbo_rub, precision: 12, scale: 2, null: false
      t.decimal :fbo_fresh_under_300_rub, precision: 12, scale: 2, null: false
      t.decimal :fbo_fresh_over_300_rub, precision: 12, scale: 2, null: false
      t.decimal :fbs_under_300_rub, precision: 12, scale: 2, null: false
      t.decimal :fbs_over_300_rub, precision: 12, scale: 2, null: false
      t.timestamps
    end

    add_index :raw_ozon_logistics_tariffs,
      [:snapshot_id, :volume_band_order, :origin_cluster_key, :destination_cluster_key],
      unique: true,
      name: "idx_raw_ozon_logistics_tariffs_identity"
    add_index :raw_ozon_logistics_tariffs,
      [:snapshot_id, :origin_cluster_key, :destination_cluster_key, :volume_min_l],
      name: "idx_raw_ozon_logistics_tariffs_lookup"

    create_table :raw_ozon_default_logistics_tariffs do |t|
      t.references :snapshot, null: false,
        foreign_key: { to_table: :raw_ozon_logistics_tariff_snapshots }
      t.integer :volume_band_order, null: false
      t.decimal :volume_min_l, precision: 10, scale: 3, null: false
      t.decimal :volume_max_l, precision: 10, scale: 3
      t.string :volume_band_label, null: false
      t.decimal :fbo_rub, precision: 12, scale: 2, null: false
      t.decimal :fbo_fresh_under_300_rub, precision: 12, scale: 2, null: false
      t.decimal :fbo_fresh_over_300_rub, precision: 12, scale: 2, null: false
      t.decimal :fbs_under_300_rub, precision: 12, scale: 2, null: false
      t.decimal :fbs_over_300_rub, precision: 12, scale: 2, null: false
      t.timestamps
    end

    add_index :raw_ozon_default_logistics_tariffs,
      [:snapshot_id, :volume_band_order],
      unique: true,
      name: "idx_raw_ozon_default_logistics_tariffs_identity"
  end
end
