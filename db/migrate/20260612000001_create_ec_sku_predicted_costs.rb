class CreateEcSkuPredictedCosts < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_sku_predicted_costs do |t|
      t.string :sku_code, null: false
      t.decimal :cost_money, precision: 12, scale: 4, null: false
      t.string :cost_currency, null: false, default: "CNY"
      t.date :effective_from, null: false
      t.date :effective_to
      t.text :note

      t.timestamps
    end

    add_index :ec_sku_predicted_costs, [:sku_code, :effective_from], name: "idx_ec_sku_predicted_costs_sku_from"
    add_foreign_key :ec_sku_predicted_costs, :ec_skus, column: :sku_code, primary_key: :sku_code
  end
end
