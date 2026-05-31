module RawWb
  class ProductPrice < ApplicationRecord
    self.table_name = 'raw_wb_product_prices'

    belongs_to :product, class_name: 'RawWb::Product'
    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
