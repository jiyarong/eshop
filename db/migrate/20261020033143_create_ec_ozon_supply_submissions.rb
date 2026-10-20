class CreateEcOzonSupplySubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_ozon_supply_submissions do |t|
      t.references :pallet_plan, null: false, foreign_key: { to_table: :ec_pallet_plans }, index: { unique: true }
      t.string :request_key, null: false
      t.string :state, null: false, default: "queued"
      t.string :draft_id
      t.string :order_id
      t.jsonb :data, null: false, default: {}
      t.text :last_error
      t.integer :poll_attempts, null: false, default: 0

      t.timestamps
    end
    add_index :ec_ozon_supply_submissions, :request_key, unique: true
    add_index :ec_ozon_supply_submissions, [:state, :updated_at]
    add_column :ec_pallets, :ozon_cargo_id, :string
  end
end
