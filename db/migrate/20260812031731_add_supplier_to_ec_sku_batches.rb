class AddSupplierToEcSkuBatches < ActiveRecord::Migration[8.1]
  def change
    add_reference :ec_sku_batches, :supplier, foreign_key: { to_table: :ec_companies, on_delete: :nullify }
  end
end
