class CreateEcSkus < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_skus do |t|
      t.string  :sku_code,   null: false
      t.string  :product_name
      t.boolean :is_active,  null: false, default: true
      t.string  :owner_name
      t.text    :memo

      t.timestamps
    end

    add_index :ec_skus, :sku_code, unique: true, name: 'idx_ec_skus_sku_code'
    add_index :ec_skus, :is_active, name: 'idx_ec_skus_is_active'
  end
end
