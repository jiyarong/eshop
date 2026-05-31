class CreateEcSkuStoreAssignments < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_sku_store_assignments do |t|
      t.string  :sku_code,     null: false
      t.string  :store_key,    null: false   # wb1_miral / wb2_taxi / wb3_zeppto / ozon1_nevastal / ozon2_nevastal2 / ozon_domos / ozon_nanokit
      t.string  :platform,     null: false   # wb / ozon
      t.string  :owner_name
      t.string  :external_id                 # WB: nm_id, Ozon: ozon_sku_id
      t.date    :listed_at
      t.boolean :is_active,    null: false, default: true

      t.timestamps
    end

    add_index :ec_sku_store_assignments, %i[sku_code store_key],
              unique: true,
              name: 'idx_ec_sku_store_assignments_unique'

    add_index :ec_sku_store_assignments, :store_key,  name: 'idx_ec_sku_store_assignments_store_key'
    add_index :ec_sku_store_assignments, :owner_name, name: 'idx_ec_sku_store_assignments_owner'

    add_foreign_key :ec_sku_store_assignments, :ec_skus, column: :sku_code, primary_key: :sku_code
  end
end
