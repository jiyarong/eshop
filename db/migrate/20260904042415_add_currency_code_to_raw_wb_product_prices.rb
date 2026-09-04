class AddCurrencyCodeToRawWbProductPrices < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_wb_product_prices, :currency_code, :string
  end
end
