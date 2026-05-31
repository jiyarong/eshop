class AddBonusTypeNameToRawWbFinanceDetails < ActiveRecord::Migration[8.0]
  def change
    add_column :raw_wb_finance_details, :bonus_type_name, :string
  end
end
