class AddDeletedAtToEcSkus < ActiveRecord::Migration[8.0]
  def change
    add_column :ec_skus, :deleted_at, :datetime
    add_index :ec_skus, :deleted_at
  end
end
