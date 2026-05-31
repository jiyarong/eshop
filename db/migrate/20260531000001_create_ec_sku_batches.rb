class CreateEcSkuBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_sku_batches do |t|
      t.string :sku_code, null: false
      t.string :batch_code, null: false
      t.string :status, null: false, default: "draft"
      t.integer :purchased_quantity, null: false, default: 0
      t.integer :received_quantity, null: false, default: 0
      t.decimal :purchase_unit_price_cny, precision: 12, scale: 4, null: false, default: 0
      t.date :expected_arrival_on
      t.date :received_on
      t.text :memo
      t.timestamps
    end

    add_index :ec_sku_batches, :sku_code
    add_index :ec_sku_batches, :batch_code, unique: true
    add_foreign_key :ec_sku_batches, :ec_skus, column: :sku_code, primary_key: :sku_code
  end
end
