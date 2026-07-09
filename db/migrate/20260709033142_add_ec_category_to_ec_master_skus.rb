class AddEcCategoryToEcMasterSkus < ActiveRecord::Migration[8.1]
  def change
    add_reference :ec_master_skus, :ec_category, foreign_key: true
  end
end
