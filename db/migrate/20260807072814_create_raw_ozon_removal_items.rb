class CreateRawOzonRemovalItems < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_ozon_removal_items do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string :source_type, null: false
      t.string :row_key, null: false
      t.string :return_id
      t.string :box_id
      t.string :sku
      t.string :offer_id
      t.string :name
      t.integer :quantity, null: false, default: 0
      t.integer :quant_count, null: false, default: 0
      t.string :stock_type
      t.string :return_state
      t.string :box_state
      t.string :clearing_warehouse_name
      t.string :destination_warehouse_name
      t.datetime :return_created_at
      t.datetime :delivery_date
      t.datetime :given_out_date
      t.datetime :utilization_date
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps
    end

    add_index :raw_ozon_removal_items, %i[account_id source_type row_key], unique: true
    add_index :raw_ozon_removal_items, %i[account_id sku return_state]
  end
end
