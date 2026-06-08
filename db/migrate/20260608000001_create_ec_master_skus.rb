class CreateEcMasterSkus < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_master_skus do |t|
      t.string :master_sku_code, null: false
      t.string :product_name
      t.string :product_name_ru
      t.boolean :is_active, null: false, default: true
      t.text :memo

      t.timestamps
    end

    add_index :ec_master_skus, :master_sku_code, unique: true
    add_index :ec_master_skus, :is_active

    add_reference :ec_skus, :master_sku, foreign_key: { to_table: :ec_master_skus }
  end
end
