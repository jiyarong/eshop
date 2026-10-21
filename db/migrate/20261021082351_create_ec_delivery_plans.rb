class CreateEcDeliveryPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_delivery_plans do |t|
      t.string :plan_no, null: false
      t.references :store, null: false, foreign_key: { to_table: :ec_stores }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.bigint :macrolocal_cluster_id, null: false
      t.string :cluster_name, null: false
      t.date :week_start, null: false
      t.date :from_date, null: false
      t.date :to_date, null: false
      t.integer :target_days, null: false, default: 28
      t.string :time_zone, null: false
      t.string :status, null: false, default: "active"
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.index :plan_no, unique: true
      t.index [:store_id, :macrolocal_cluster_id, :week_start], name: "idx_delivery_plans_destination_week"
    end

    create_table :ec_delivery_plan_items do |t|
      t.references :delivery_plan, null: false, foreign_key: { to_table: :ec_delivery_plans }
      t.string :sku_code, null: false
      t.integer :units, null: false
      t.timestamps
      t.index [:delivery_plan_id, :sku_code], unique: true, name: "idx_delivery_plan_items_unique"
    end

    add_reference :ec_pallet_plans, :delivery_plan, foreign_key: { to_table: :ec_delivery_plans }
  end
end
