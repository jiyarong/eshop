class AddCustomerPriceToRawOzonProductPrices < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_ozon_product_prices, :customer_price, :decimal, precision: 18, scale: 2
  end
end
