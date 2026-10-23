class CreateEcOwnWarehouseSkuCostAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_own_warehouse_sku_cost_allocations do |t|
      t.references :sku, null: false, foreign_key: { to_table: :ec_skus }
      t.references :own_warehouse_cost_period, foreign_key: { to_table: :ec_own_warehouse_cost_periods }
      t.string :own_warehouse_code, null: false
      t.date :week_start, null: false
      t.date :week_end, null: false
      t.integer :allocation_version, null: false, default: 1
      t.boolean :is_current, null: false, default: true
      t.decimal :unit_volume_m3, precision: 18, scale: 8
      t.decimal :on_hand_quantity, precision: 18, scale: 4
      t.decimal :on_hand_volume_m3, precision: 18, scale: 8
      t.decimal :fbs_outbound_quantity, precision: 18, scale: 4
      t.decimal :fbs_outbound_volume_m3, precision: 18, scale: 8
      t.decimal :fbo_outbound_quantity, precision: 18, scale: 4
      t.decimal :fbo_outbound_volume_m3, precision: 18, scale: 8
      t.decimal :storage_cost, precision: 18, scale: 2, default: 0, null: false
      t.decimal :transport_cost, precision: 18, scale: 2, default: 0, null: false
      t.decimal :labor_cost, precision: 18, scale: 2, default: 0, null: false
      t.decimal :total_cost, precision: 18, scale: 2, default: 0, null: false
      t.decimal :outbound_quantity, precision: 18, scale: 4
      t.decimal :cost_per_outbound_unit, precision: 18, scale: 6
      t.jsonb :calculation_inputs, null: false, default: {}
      t.string :status, null: false, default: "calculated"
      t.datetime :calculated_at

      t.timestamps
    end
    add_index :ec_own_warehouse_sku_cost_allocations, [:own_warehouse_code, :sku_id, :week_start, :allocation_version], unique: true, name: "idx_own_wh_allocations_revision"
    add_index :ec_own_warehouse_sku_cost_allocations, [:own_warehouse_code, :sku_id, :week_start], unique: true, where: "is_current", name: "idx_own_wh_allocations_current"
    add_check_constraint :ec_own_warehouse_sku_cost_allocations, "storage_cost >= 0 AND transport_cost >= 0 AND labor_cost >= 0 AND total_cost = storage_cost + transport_cost + labor_cost", name: "own_wh_allocations_values"
    add_check_constraint :ec_own_warehouse_sku_cost_allocations, "week_end = week_start + 6 AND EXTRACT(ISODOW FROM week_start) = 1 AND allocation_version > 0", name: "own_wh_allocations_natural_week"
  end
end
