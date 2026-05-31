module RawOzon
  class PostingDestination < ApplicationRecord
    self.table_name = 'raw_ozon_posting_destinations'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'

    scope :belarus,  -> { where(is_belarus: true) }
    scope :export,   -> { where(is_belarus: false) }
  end
end
