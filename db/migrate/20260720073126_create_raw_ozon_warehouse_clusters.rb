class CreateRawOzonWarehouseClusters < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_ozon_warehouse_clusters do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint :warehouse_id, null: false
      t.string :warehouse_name, null: false
      t.string :normalized_warehouse_name, null: false
      t.bigint :macrolocal_cluster_id
      t.string :cluster_name
      t.string :country_name
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false

      t.timestamps
    end

    add_index :raw_ozon_warehouse_clusters,
      [:account_id, :warehouse_id],
      unique: true,
      name: "idx_raw_ozon_warehouse_clusters_unique"
    add_index :raw_ozon_warehouse_clusters,
      [:account_id, :normalized_warehouse_name],
      name: "idx_raw_ozon_warehouse_clusters_lookup"
  end
end
