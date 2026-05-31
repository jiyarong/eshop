module RawOzon
  class Review < ApplicationRecord
    self.table_name = 'raw_ozon_reviews'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
