class AddDetailsToRawWbSupplies < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_wb_supplies, :warehouse_id, :bigint
    add_column :raw_wb_supplies, :warehouse_name, :string
    add_column :raw_wb_supplies, :actual_warehouse_id, :bigint
    add_column :raw_wb_supplies, :actual_warehouse_name, :string
    add_column :raw_wb_supplies, :transit_warehouse_id, :bigint
    add_column :raw_wb_supplies, :transit_warehouse_name, :string
    add_column :raw_wb_supplies, :acceptance_cost, :decimal, precision: 15, scale: 2
    add_column :raw_wb_supplies, :paid_acceptance_coefficient, :decimal, precision: 10, scale: 4
    add_column :raw_wb_supplies, :reject_reason, :text
    add_column :raw_wb_supplies, :supplier_assign_name, :string
    add_column :raw_wb_supplies, :storage_coefficient, :decimal, precision: 10, scale: 4
    add_column :raw_wb_supplies, :delivery_coefficient, :decimal, precision: 10, scale: 4
    add_column :raw_wb_supplies, :detail_quantity, :integer
    add_column :raw_wb_supplies, :ready_for_sale_quantity, :integer
    add_column :raw_wb_supplies, :accepted_quantity, :integer
    add_column :raw_wb_supplies, :unloading_quantity, :integer
    add_column :raw_wb_supplies, :depersonalized_quantity, :integer
    add_column :raw_wb_supplies, :can_show_quantity, :boolean
    add_column :raw_wb_supplies, :raw_detail_json, :jsonb, null: false, default: {}
  end
end
