module RawWb
  class ProductPriceHistory < ApplicationRecord
    self.table_name = 'raw_wb_product_price_histories'

    belongs_to :product, class_name: 'RawWb::Product'
  end
end
