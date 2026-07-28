class AddOperationStatusToEcSkus < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_skus, :operation_status, :string, default: "normal", null: false
    add_index :ec_skus, :operation_status
  end
end
