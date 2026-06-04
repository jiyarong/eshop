class CreateEcOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_orders do |t|
      t.string :platform, null: false
      t.references :store, null: false, foreign_key: { to_table: :ec_stores }
      t.string :external_order_id
      t.string :external_order_number
      t.string :order_key, null: false
      t.string :order_status, null: false, default: "unknown"
      t.string :source_status
      t.string :source_substatus
      t.datetime :ordered_at
      t.datetime :in_process_at
      t.string :buyer_city
      t.string :buyer_region
      t.string :buyer_country
      t.string :payment_method_source
      t.boolean :is_legal_entity, null: false, default: false
      t.jsonb :source_payload
      t.datetime :synced_at
      t.timestamps
    end

    add_index :ec_orders, [:platform, :store_id, :order_key],
              unique: true, name: "idx_ec_orders_unique_order_key"
    add_index :ec_orders, [:platform, :store_id, :external_order_number],
              name: "idx_ec_orders_external_order_number"
    add_index :ec_orders, :order_status
    add_index :ec_orders, :ordered_at

    create_table :ec_order_fulfillments do |t|
      t.references :order, null: false, foreign_key: { to_table: :ec_orders }
      t.string :platform, null: false
      t.references :store, null: false, foreign_key: { to_table: :ec_stores }
      t.string :external_fulfillment_id, null: false
      t.string :fulfillment_key, null: false
      t.string :fulfillment_type, null: false, default: "unknown"
      t.string :status, null: false, default: "unknown"
      t.string :source_status
      t.string :source_substatus
      t.string :warehouse_name
      t.string :warehouse_external_id
      t.string :delivery_method_name
      t.string :delivery_type_source
      t.string :tracking_number
      t.datetime :shipped_at
      t.datetime :delivered_at
      t.datetime :cancelled_at
      t.string :cancel_reason_source
      t.string :raw_source_type
      t.bigint :raw_source_id
      t.datetime :synced_at
      t.timestamps
    end

    add_index :ec_order_fulfillments, [:platform, :store_id, :fulfillment_key],
              unique: true, name: "idx_ec_order_fulfillments_unique_key"
    add_index :ec_order_fulfillments, [:raw_source_type, :raw_source_id],
              name: "idx_ec_order_fulfillments_raw_source"
    add_index :ec_order_fulfillments, :status

    create_table :ec_order_items do |t|
      t.references :order, null: false, foreign_key: { to_table: :ec_orders }
      t.references :fulfillment, foreign_key: { to_table: :ec_order_fulfillments }
      t.string :platform, null: false
      t.references :store, null: false, foreign_key: { to_table: :ec_stores }
      t.string :external_item_id
      t.string :platform_sku_id
      t.string :offer_id
      t.string :sku_code
      t.string :product_name_source
      t.integer :quantity, null: false, default: 1
      t.decimal :unit_price, precision: 18, scale: 2
      t.decimal :old_unit_price, precision: 18, scale: 2
      t.string :currency_code
      t.decimal :payout, precision: 18, scale: 2
      t.decimal :commission_amount, precision: 18, scale: 2
      t.decimal :commission_percent, precision: 8, scale: 2
      t.decimal :discount_amount, precision: 18, scale: 2
      t.decimal :discount_percent, precision: 8, scale: 2
      t.jsonb :item_payload
      t.datetime :synced_at
      t.timestamps
    end

    add_index :ec_order_items, [:platform, :store_id, :external_item_id],
              name: "idx_ec_order_items_external_item"
    add_index :ec_order_items, [:platform, :store_id, :offer_id],
              name: "idx_ec_order_items_offer"
    add_index :ec_order_items, :platform_sku_id
    add_index :ec_order_items, :sku_code
    add_foreign_key :ec_order_items, :ec_skus, column: :sku_code, primary_key: :sku_code

    create_table :ec_order_source_links do |t|
      t.references :order, null: false, foreign_key: { to_table: :ec_orders }
      t.references :fulfillment, foreign_key: { to_table: :ec_order_fulfillments }
      t.references :item, foreign_key: { to_table: :ec_order_items }
      t.string :platform, null: false
      t.string :source_type, null: false
      t.bigint :source_id, null: false
      t.string :source_key
      t.string :source_role, null: false, default: "primary"
      t.datetime :synced_at
      t.timestamps
    end

    add_index :ec_order_source_links, [:source_type, :source_id, :source_role],
              unique: true, name: "idx_ec_order_source_links_unique_source"
    add_index :ec_order_source_links, [:platform, :source_key],
              name: "idx_ec_order_source_links_source_key"
  end
end
