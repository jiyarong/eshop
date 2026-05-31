module RawOzon
  class ProductPrice < ApplicationRecord
    self.table_name = 'raw_ozon_product_prices'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
