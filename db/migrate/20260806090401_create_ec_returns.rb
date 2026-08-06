class CreateEcReturns < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_returns do |t|
      t.string :platform, null: false
      t.references :store, null: false, foreign_key: { to_table: :ec_stores }
      t.references :order, foreign_key: { to_table: :ec_orders }
      t.string :return_key, null: false
      t.string :return_type, null: false
      t.string :process_status, null: false, default: "unknown"
      t.string :inventory_location, null: false, default: "unknown"
      t.string :inventory_condition, null: false, default: "unknown"
      t.string :refund_status, null: false, default: "none"
      t.string :external_return_id
      t.string :external_order_id
      t.string :external_order_number
      t.string :external_posting_number
      t.datetime :requested_at
      t.datetime :returned_to_platform_at
      t.datetime :returned_to_seller_at
      t.datetime :completed_at
      t.string :source_status
      t.string :source_substatus
      t.jsonb :source_payload, null: false, default: {}
      t.datetime :synced_at
      t.timestamps
    end

    add_index :ec_returns, %i[platform store_id return_key], unique: true
    add_index :ec_returns, :process_status
    add_index :ec_returns, :inventory_location
  end
end
