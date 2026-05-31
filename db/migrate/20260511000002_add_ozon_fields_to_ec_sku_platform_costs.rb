class AddOzonFieldsToEcSkuPlatformCosts < ActiveRecord::Migration[8.0]
  def change
    change_table :ec_sku_platform_costs do |t|
      # WB: 基础运费常数（Tab1=60, Tab2=46），nil 时默认 60
      t.decimal :wb_logistics_base_rub,      precision: 8,  scale: 2

      # Ozon: 去程运费参数（FBO: 87.44/15.25；FBS: 117.94/23.39）
      t.decimal :ozon_fwd_base_rub,          precision: 8,  scale: 2
      t.decimal :ozon_fwd_per_liter_rub,     precision: 8,  scale: 2

      # Ozon: 返程运费参数（FBO/FBS 均使用 FBO 费率）
      t.decimal :ozon_ret_base_rub,          precision: 8,  scale: 2
      t.decimal :ozon_ret_per_liter_rub,     precision: 8,  scale: 2

      # Ozon: 仓库固定费用
      t.decimal :ozon_warehouse_op_rub,      precision: 8,  scale: 2  # FBO:25 / FBS:30
      t.decimal :ozon_fbs_delivery_rub,      precision: 8,  scale: 2  # FBS 专有配送费(25)

      # Ozon: 双市场计划售价（WB 继续用 target_price_rub）
      t.decimal :target_price_rf_rub,        precision: 12, scale: 2
      t.decimal :target_price_by_rub,        precision: 12, scale: 2
    end
  end
end
