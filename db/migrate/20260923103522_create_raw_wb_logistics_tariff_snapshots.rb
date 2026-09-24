class CreateRawWbLogisticsTariffSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_wb_logistics_tariff_snapshots do |t|
      t.string :status, null: false, default: "running"
      t.references :source_account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.date :requested_date, null: false
      t.date :effective_from
      t.date :effective_to
      t.datetime :fetched_at, null: false
      t.datetime :completed_at
      t.bigint :response_bytes
      t.integer :item_count
      t.string :error_class
      t.text :error_message
      t.jsonb :raw_json
      t.boolean :is_current, null: false, default: false

      t.timestamps
    end

    add_index :raw_wb_logistics_tariff_snapshots, :is_current,
      unique: true, where: "is_current", name: "idx_raw_wb_logistics_tariff_snapshots_current"
    add_index :raw_wb_logistics_tariff_snapshots, [ :requested_date, :status ],
      name: "idx_raw_wb_logistics_tariff_snapshots_requested_status"
  end
end
