module RawOzon
  class ProductAttribute < ApplicationRecord
    self.table_name = 'raw_ozon_product_attributes'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
