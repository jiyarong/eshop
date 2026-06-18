class AddStatusIdToRawWbSupplies < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_wb_supplies, :status_id,        :integer
    add_column :raw_wb_supplies, :preorder_id,      :bigint
    add_column :raw_wb_supplies, :box_type_id,      :integer
    add_column :raw_wb_supplies, :is_box_on_pallet, :boolean
    add_column :raw_wb_supplies, :supply_date,      :datetime
    add_column :raw_wb_supplies, :fact_date,        :datetime
    add_column :raw_wb_supplies, :updated_at_wb,    :datetime

    add_index :raw_wb_supplies, %i[account_id preorder_id],
              unique: true, name: 'idx_raw_wb_supplies_account_preorder',
              if_not_exists: true
  end
end
