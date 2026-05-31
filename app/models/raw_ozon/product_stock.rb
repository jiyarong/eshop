module RawOzon
  class ProductStock < ApplicationRecord
    self.table_name = 'raw_ozon_product_stocks'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
