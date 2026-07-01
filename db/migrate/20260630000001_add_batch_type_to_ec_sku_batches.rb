class AddBatchTypeToEcSkuBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :ec_sku_batches, :batch_type, :integer, null: false, default: 1
    add_column :ec_sku_batches, :defect_offset_note, :string
  end
end
