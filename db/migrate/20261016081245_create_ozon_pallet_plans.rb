class CreateOzonPalletPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_pallet_plans do |t|
      t.string :plan_no, null: false
      t.references :store, null: false, foreign_key: { to_table: :ec_stores }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.bigint :macrolocal_cluster_id, null: false
      t.string :cluster_name, null: false
      t.string :status, null: false, default: "draft"
      t.date :from_date, null: false
      t.date :to_date, null: false
      t.integer :target_days, null: false, default: 28
      t.string :time_zone, null: false
      t.jsonb :settings, null: false, default: {}
      t.jsonb :calculation, null: false, default: {}
      t.string :supply_order_number
      t.string :ozon_order_id
      t.string :platform_status
      t.datetime :platform_synced_at
      t.jsonb :platform_snapshot, null: false, default: {}
      t.text :sync_error
      t.text :platform_check_note
      t.datetime :confirmed_at
      t.datetime :dispatched_at
      t.datetime :closed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.index :plan_no, unique: true
      t.index [:store_id, :macrolocal_cluster_id, :status], name: "idx_pallet_plans_workbench"
      t.index [:store_id, :ozon_order_id], unique: true, where: "ozon_order_id IS NOT NULL AND status <> 'cancelled'", name: "idx_pallet_plans_bound_order"
    end
    create_table :ec_pallet_plan_items do |t|
      t.references :pallet_plan, null: false, foreign_key: { to_table: :ec_pallet_plans }
      t.string :sku_code, null: false
      t.references :sku_product, null: false, foreign_key: { to_table: :ec_sku_products }
      t.string :platform_sku_id, null: false
      t.integer :boxes, null: false
      t.integer :pcs, null: false
      t.integer :units, null: false
      t.integer :shortage, null: false, default: 0
      t.jsonb :packaging, null: false, default: {}
      t.integer :platform_covered_units, null: false, default: 0
      t.jsonb :inventory_baseline, null: false, default: {}
      t.timestamps
      t.index [:pallet_plan_id, :sku_code], unique: true
      t.index :sku_code
    end
    create_table :ec_pallets do |t|
      t.references :pallet_plan, null: false, foreign_key: { to_table: :ec_pallet_plans }
      t.integer :position, null: false
      t.jsonb :layout, null: false, default: {}
      t.jsonb :metrics, null: false, default: {}
      t.string :ozon_supply_id
      t.bigint :storage_warehouse_id
      t.timestamps
      t.index [:pallet_plan_id, :position], unique: true
    end
    create_table :ec_pallet_items do |t|
      t.references :pallet, null: false, foreign_key: { to_table: :ec_pallets }
      t.references :pallet_plan_item, null: false, foreign_key: { to_table: :ec_pallet_plan_items }
      t.integer :boxes, null: false
      t.integer :units, null: false
      t.jsonb :layout, null: false, default: {}
      t.timestamps
      t.index [:pallet_id, :pallet_plan_item_id], unique: true, name: "idx_pallet_items_unique"
    end
  end
end
