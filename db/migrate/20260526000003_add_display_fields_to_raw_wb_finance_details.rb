class AddDisplayFieldsToRawWbFinanceDetails < ActiveRecord::Migration[8.0]
  def change
    add_column :raw_wb_finance_details, :vw,               :decimal, precision: 15, scale: 2
    add_column :raw_wb_finance_details, :country,          :string
    add_column :raw_wb_finance_details, :office_name,      :string
    add_column :raw_wb_finance_details, :ppvz_office_name, :string
    add_column :raw_wb_finance_details, :delivery_method,  :string
  end
end
