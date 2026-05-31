module RawWb
  class Review < ApplicationRecord
    self.table_name = 'raw_wb_reviews'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
