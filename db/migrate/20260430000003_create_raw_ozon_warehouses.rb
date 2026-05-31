class CreateRawOzonWarehouses < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_warehouses do |t|
      t.references :account,    null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint  :warehouse_id,  null: false
      t.string  :name
      t.boolean :is_rfbs,       default: false
      t.boolean :has_entrusted_acceptance, default: false
      t.string  :status
      t.jsonb   :raw_json
      t.datetime :synced_at
      t.index [:account_id, :warehouse_id], unique: true
    end

    create_table :raw_ozon_supply_orders do |t|
      t.references :account,    null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string  :supply_order_id, null: false
      t.string  :status
      t.datetime :created_at
      t.jsonb   :timeslot
      t.jsonb   :items
      t.jsonb   :raw_json,      null: false
      t.datetime :synced_at
      t.index [:account_id, :supply_order_id], unique: true
      t.index [:account_id, :status]
    end
  end
end
