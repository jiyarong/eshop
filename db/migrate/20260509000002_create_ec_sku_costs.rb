class CreateEcSkuCosts < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_sku_costs do |t|
      t.string  :sku_code,           null: false
      t.decimal :purchase_price_cny, precision: 10, scale: 4
      t.decimal :freight_to_by_cny,  precision: 10, scale: 4
      t.decimal :customs_misc_cny,   precision: 10, scale: 4
      t.decimal :customs_duty_rate,  precision: 6,  scale: 4, default: 0.10
      t.decimal :import_vat_rate,    precision: 6,  scale: 4, default: 0.20
      t.decimal :pkg_length_cm,      precision: 8,  scale: 2
      t.decimal :pkg_width_cm,       precision: 8,  scale: 2
      t.decimal :pkg_height_cm,      precision: 8,  scale: 2
      t.decimal :damage_rate,        precision: 6,  scale: 4, default: 0.0
      t.decimal :misc_cost_cny,      precision: 10, scale: 4, default: 0.0
      t.text    :memo

      t.timestamps
    end

    add_index :ec_sku_costs, :sku_code, unique: true, name: 'idx_ec_sku_costs_sku_code'
    add_foreign_key :ec_sku_costs, :ec_skus, column: :sku_code, primary_key: :sku_code
  end
end
