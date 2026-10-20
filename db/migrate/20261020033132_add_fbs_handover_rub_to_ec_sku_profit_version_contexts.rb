# Ozon FBS: what the platform charges per unit to take the parcel over from the seller (drop-off
# at a pickup point or sorting centre, last mile). Replaces the FBO warehouse operation fee.
class AddFbsHandoverRubToEcSkuProfitVersionContexts < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_sku_profit_version_contexts, :fbs_handover_rub, :decimal, precision: 20, scale: 8
  end
end
