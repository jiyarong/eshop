class AddPerformanceCredentialsToRawOzonSellerAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :raw_ozon_seller_accounts, :performance_client_id, :string
    add_column :raw_ozon_seller_accounts, :performance_client_secret, :text
  end
end
