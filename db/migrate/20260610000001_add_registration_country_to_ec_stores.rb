class AddRegistrationCountryToEcStores < ActiveRecord::Migration[8.0]
  def change
    add_column :ec_stores, :registration_country, :string unless column_exists?(:ec_stores, :registration_country)
  end
end
