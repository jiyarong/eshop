class CreateEcSkuMarketingStates < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_sku_marketing_states do |t|
      t.references :sku, null: false, index: false, foreign_key: { to_table: :ec_skus, on_delete: :cascade }
      t.string :grade, null: false
      t.string :stage, null: false
      t.datetime :effective_at, null: false
      t.datetime :ended_at
      t.references :changed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :note

      t.timestamps
    end

    add_index :ec_sku_marketing_states, [ :sku_id, :effective_at ], name: "idx_ec_sku_marketing_states_sku_effective"
    add_index :ec_sku_marketing_states, :sku_id, unique: true, where: "ended_at IS NULL", name: "idx_ec_sku_marketing_states_current"
    add_check_constraint :ec_sku_marketing_states, "grade IN ('S', 'A', 'B', 'C')", name: "ec_sku_marketing_states_grade_check"
    add_check_constraint :ec_sku_marketing_states, "stage IN ('new', 'grw', 'mat', 'clr')", name: "ec_sku_marketing_states_stage_check"
    add_check_constraint :ec_sku_marketing_states, "ended_at IS NULL OR ended_at >= effective_at", name: "ec_sku_marketing_states_period_check"
  end
end
