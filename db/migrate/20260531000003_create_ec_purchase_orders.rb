class CreateEcPurchaseOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_purchase_orders do |t|
      t.string :order_no, null: false
      t.references :supplier, null: false, foreign_key: { to_table: :ec_suppliers }
      t.date :ordered_on
      t.string :status, null: false, default: "draft"
      t.string :currency, null: false, default: "CNY"
      t.text :memo
      t.timestamps
    end

    add_index :ec_purchase_orders, :order_no, unique: true
    add_index :ec_purchase_orders, :status

    create_table :ec_purchase_order_items do |t|
      t.references :purchase_order, null: false, foreign_key: { to_table: :ec_purchase_orders }
      t.string :sku_code, null: false
      t.references :sku_batch, null: false, foreign_key: { to_table: :ec_sku_batches }
      t.integer :quantity, null: false
      t.decimal :unit_price_cny, precision: 12, scale: 4, null: false
      t.text :memo
      t.timestamps
    end

    add_index :ec_purchase_order_items, [:purchase_order_id, :sku_batch_id], unique: true, name: "idx_ec_po_items_order_batch_unique"
    add_index :ec_purchase_order_items, :sku_code
    add_foreign_key :ec_purchase_order_items, :ec_skus, column: :sku_code, primary_key: :sku_code
  end
end
