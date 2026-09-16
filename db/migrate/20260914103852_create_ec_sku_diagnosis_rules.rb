class CreateEcSkuDiagnosisRules < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_sku_diagnosis_rules do |t|
      t.string :name, null: false
      t.text :prompt, null: false
      t.string :frequency, null: false, default: "daily"
      t.boolean :enabled, null: false, default: true
      t.jsonb :configuration, null: false, default: { "context_keys" => %w[base inventory lifecycle profit sales_funnel advertise_per_week ec_orders_full_period supply_orders_full_period operation_actions_full_period warehouse_recommendation search_terms_per_week] }

      t.timestamps
    end
    add_index :ec_sku_diagnosis_rules, :enabled
    add_index :ec_sku_diagnosis_rules, :frequency
  end
end
