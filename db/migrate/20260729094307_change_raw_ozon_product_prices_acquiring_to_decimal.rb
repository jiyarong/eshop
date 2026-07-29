class ChangeRawOzonProductPricesAcquiringToDecimal < ActiveRecord::Migration[8.1]
  def change
    change_column :raw_ozon_product_prices, :acquiring, :decimal, precision: 18, scale: 2
  end
end
