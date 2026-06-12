module RawOzon
  class ProductQueryDetail < ApplicationRecord
    self.table_name = 'raw_ozon_product_query_details'

    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
