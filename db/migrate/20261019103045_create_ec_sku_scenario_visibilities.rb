# Which pricing scenarios a SKU's workbench shows. A row exists only once somebody hides (or
# restores) a scenario; a scenario without a row is shown. Hiding never touches the scenario's
# data in any version, so it is not an edit of the version.
class CreateEcSkuScenarioVisibilities < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_sku_scenario_visibilities do |t|
      t.references :sku, null: false, foreign_key: { to_table: :ec_skus }
      t.string :platform, null: false
      t.string :market, null: false
      t.string :delivery_mode, null: false
      t.string :warehouse_region, null: false, default: "main"
      t.string :company_type, null: false
      t.boolean :hidden, null: false, default: false
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :ec_sku_scenario_visibilities,
      %i[sku_id platform market delivery_mode warehouse_region company_type],
      unique: true, name: "idx_ec_sku_scenario_visibilities_identity"
  end
end
