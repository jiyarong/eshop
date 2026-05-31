class AddCompanyTypeToSellerAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :raw_wb_seller_accounts,   :company_type, :string
    add_column :raw_ozon_seller_accounts, :company_type, :string
  end
end
