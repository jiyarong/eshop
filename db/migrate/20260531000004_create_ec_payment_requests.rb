class CreateEcPaymentRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_payment_requests do |t|
      t.references :purchase_order, null: false, foreign_key: { to_table: :ec_purchase_orders }
      t.string :payment_type, null: false
      t.decimal :amount_cny, precision: 12, scale: 4, null: false
      t.string :status, null: false, default: "pending"
      t.date :requested_on
      t.datetime :approved_at
      t.datetime :paid_at
      t.text :memo
      t.timestamps
    end

    add_index :ec_payment_requests, :status
    add_index :ec_payment_requests, :payment_type
  end
end
