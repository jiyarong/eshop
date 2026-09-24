class CreateEcSkuProfitScenarioVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_sku_profit_scenario_versions do |t|
      t.references :sku, null: false, foreign_key: { to_table: :ec_skus }
      t.string :platform, null: false
      t.string :market, null: false, default: "RU"
      t.string :delivery_mode, null: false
      t.string :warehouse_region
      t.string :company_type
      t.date :effective_from, null: false
      t.date :effective_to
      t.jsonb :parameters, null: false, default: {}
      t.text :note

      t.timestamps
    end
    add_index :ec_sku_profit_scenario_versions, %i[sku_id platform market delivery_mode warehouse_region company_type effective_from], name: "idx_sku_profit_versions_scenario_start"
  end
end
