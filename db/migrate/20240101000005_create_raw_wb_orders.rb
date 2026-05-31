class CreateRawWbOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_orders do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.bigint :wb_order_id, index: { unique: true }
      t.string :order_uid
      t.string :srid
      t.string :delivery_type, null: false
      t.bigint :nm_id
      t.bigint :chrt_id
      t.string :article
      t.string :barcode
      t.string :supplier_status
      t.string :wb_status
      t.decimal :price, precision: 15, scale: 2
      t.decimal :converted_price, precision: 15, scale: 2
      t.integer :currency_code, default: 643
      t.references :warehouse, foreign_key: { to_table: :raw_wb_warehouses }
      t.string :wb_office
      t.jsonb :required_meta
      t.jsonb :optional_meta
      t.jsonb :buyer_info
      t.boolean :is_zero_order, default: false
      t.datetime :created_at, null: false
      t.datetime :updated_at
      t.datetime :synced_at
    end

    create_table :raw_wb_order_metas do |t|
      t.references :order, null: false, foreign_key: { to_table: :raw_wb_orders }
      t.string :meta_type
      t.string :value
      t.timestamps
    end

    create_table :raw_wb_order_status_histories do |t|
      t.references :order, null: false, foreign_key: { to_table: :raw_wb_orders }
      t.string :supplier_status
      t.string :wb_status
      t.datetime :changed_at, default: -> { 'CURRENT_TIMESTAMP' }
    end

    create_table :raw_wb_supplies do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.string :wb_supply_id, index: { unique: true }
      t.string :name
      t.string :supply_type, default: 'fbs'
      t.boolean :is_done, default: false
      t.datetime :supply_created_at
      t.datetime :closed_at
      t.datetime :scan_dt
      t.datetime :synced_at
    end

    create_table :raw_wb_supply_orders, id: false do |t|
      t.references :supply, null: false, foreign_key: { to_table: :raw_wb_supplies }
      t.references :order, null: false, foreign_key: { to_table: :raw_wb_orders }
      t.datetime :added_at, default: -> { 'CURRENT_TIMESTAMP' }
      t.index [:supply_id, :order_id], unique: true
    end

    create_table :raw_wb_supply_boxes do |t|
      t.references :supply, null: false, foreign_key: { to_table: :raw_wb_supplies }
      t.bigint :wb_box_id
      t.string :barcode
      t.timestamps
    end
  end
end
