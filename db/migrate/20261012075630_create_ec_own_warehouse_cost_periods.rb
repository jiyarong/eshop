class CreateEcOwnWarehouseCostPeriods < ActiveRecord::Migration[8.1]
  def change
    enable_extension "btree_gist" unless extension_enabled?("btree_gist")
    create_table :ec_own_warehouse_cost_periods do |t|
      t.string :own_warehouse_code, null: false
      t.date :effective_from, null: false
      t.date :effective_to
      t.decimal :total_operating_cost, precision: 18, scale: 2, null: false
      t.string :billing_unit, null: false, default: "week"
      t.string :currency, null: false, default: "CNY"
      t.decimal :storage_ratio, precision: 8, scale: 6, null: false, default: 0
      t.decimal :transport_ratio, precision: 8, scale: 6, null: false, default: 0
      t.decimal :labor_ratio, precision: 8, scale: 6, null: false, default: 0
      t.decimal :fbo_labor_weight, precision: 8, scale: 6, null: false, default: 0
      t.string :status, null: false, default: "draft"
      t.string :source_reference
      t.text :note
      t.bigint :created_by_id
      t.bigint :confirmed_by_id
      t.datetime :confirmed_at

      t.timestamps
    end
    add_exclusion_constraint :ec_own_warehouse_cost_periods,
      "own_warehouse_code WITH =, daterange(effective_from, effective_to, '[]') WITH &&",
      using: :gist, where: "status IN ('confirmed', 'superseded')", name: "own_wh_cost_periods_no_overlap"
    add_index :ec_own_warehouse_cost_periods, [:own_warehouse_code, :effective_from], unique: true, name: "idx_own_wh_cost_periods_start"
    add_check_constraint :ec_own_warehouse_cost_periods, "effective_to IS NULL OR effective_to >= effective_from", name: "own_wh_cost_periods_dates"
    add_check_constraint :ec_own_warehouse_cost_periods, "total_operating_cost >= 0 AND storage_ratio >= 0 AND transport_ratio >= 0 AND labor_ratio >= 0 AND fbo_labor_weight >= 0 AND storage_ratio + transport_ratio + labor_ratio = 1", name: "own_wh_cost_periods_values"
    add_check_constraint :ec_own_warehouse_cost_periods, "billing_unit IN ('week','month','quarter')", name: "own_wh_cost_periods_billing_unit"
    add_check_constraint :ec_own_warehouse_cost_periods, "status IN ('draft','confirmed','superseded')", name: "own_wh_cost_periods_status"
  end
end
