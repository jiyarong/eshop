class AddPurchaseDateToEcSkuBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_sku_batches, :purchase_date, :date
  end
end
