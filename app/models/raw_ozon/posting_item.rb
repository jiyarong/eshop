module RawOzon
  class PostingItem < ApplicationRecord
    self.table_name = 'raw_ozon_posting_items'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
