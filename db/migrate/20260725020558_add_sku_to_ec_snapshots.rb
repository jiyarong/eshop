class AddSkuToEcSnapshots < ActiveRecord::Migration[8.1]
  def change
    remove_index :ec_snapshots, [ :snapshot_type, :snapshot_date ]

    add_reference :ec_snapshots, :sku, null: true, foreign_key: { to_table: :ec_skus }
    add_index :ec_snapshots, [ :snapshot_type, :snapshot_date ],
              unique: true,
              where: "sku_id IS NULL",
              name: "idx_ec_snapshots_global_unique"
    add_index :ec_snapshots, [ :snapshot_type, :snapshot_date, :sku_id ],
              unique: true,
              where: "sku_id IS NOT NULL",
              name: "idx_ec_snapshots_sku_daily_unique"
  end
end
