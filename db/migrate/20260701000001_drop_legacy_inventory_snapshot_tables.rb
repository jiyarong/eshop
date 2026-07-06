class DropLegacyInventorySnapshotTables < ActiveRecord::Migration[8.0]
  def up
    drop_table :ec_inventory_snapshots, if_exists: true
    drop_table :ec_inventory_totals, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "legacy inventory snapshot tables have been removed"
  end
end
