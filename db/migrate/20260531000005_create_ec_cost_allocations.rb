class CreateEcCostAllocations < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_cost_allocations do |t|
      t.string :allocation_no, null: false
      t.string :cost_type, null: false
      t.string :allocation_method, null: false
      t.decimal :total_amount_cny, precision: 12, scale: 4, null: false
      t.date :allocated_on
      t.string :status, null: false, default: "draft"
      t.text :memo
      t.timestamps
    end

    add_index :ec_cost_allocations, :allocation_no, unique: true
    add_index :ec_cost_allocations, :cost_type
    add_index :ec_cost_allocations, :status

    create_table :ec_cost_allocation_items do |t|
      t.references :cost_allocation, null: false, foreign_key: { to_table: :ec_cost_allocations }
      t.references :sku_batch, null: false, foreign_key: { to_table: :ec_sku_batches }
      t.decimal :amount_cny, precision: 12, scale: 4, null: false
      t.text :memo
      t.timestamps
    end

    add_index :ec_cost_allocation_items, [:cost_allocation_id, :sku_batch_id], unique: true, name: "idx_ec_cost_alloc_items_unique"
  end
end
