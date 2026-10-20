# Where an order's buyer_country came from, so a stronger source can replace a weaker one later
# (stats_order / ozon_cluster > city > buyer_currency). See Ec::BuyerCountry.
class AddBuyerCountrySourceToEcOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :ec_orders, :buyer_country_source, :string
    add_index :ec_orders, %i[platform buyer_country], name: "index_ec_orders_on_platform_and_buyer_country"
  end
end
