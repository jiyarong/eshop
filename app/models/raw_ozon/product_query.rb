module RawOzon
  class ProductQuery < ApplicationRecord
    self.table_name = 'raw_ozon_product_queries'

    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
