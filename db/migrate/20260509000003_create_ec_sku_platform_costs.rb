class CreateEcSkuPlatformCosts < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_sku_platform_costs do |t|
      t.string  :sku_code,              null: false
      t.string  :platform,              null: false  # wb / ozon
      t.string  :delivery_mode,         null: false  # fbo / fbs
      t.string  :company_type,          null: false  # general / small

      # 平台运费
      t.decimal :logistics_coeff,       precision: 6,  scale: 4
      t.decimal :fbo_delivery_cny,      precision: 10, scale: 4, default: 0.0

      # 退货
      t.decimal :return_rate,           precision: 6,  scale: 4

      # 其他平台费用
      t.decimal :storage_30d_cny,       precision: 10, scale: 4, default: 0.0
      t.decimal :acquiring_rate,        precision: 6,  scale: 4
      t.decimal :commission_rate,       precision: 6,  scale: 4
      t.decimal :ad_spend_rate,         precision: 6,  scale: 4

      # 税务
      t.decimal :sales_tax_rate,        precision: 6,  scale: 4  # general: null, small: 0.06

      # 汇率与目标价
      t.decimal :exchange_rate_rub_cny, precision: 8,  scale: 4
      t.decimal :target_price_rub,      precision: 12, scale: 2
      t.decimal :min_price_rub,         precision: 12, scale: 2

      t.timestamps
    end

    add_index :ec_sku_platform_costs,
              %i[sku_code platform delivery_mode company_type],
              unique: true,
              name: 'idx_ec_sku_platform_costs_unique'

    add_foreign_key :ec_sku_platform_costs, :ec_skus, column: :sku_code, primary_key: :sku_code
  end
end
