module RawOzon
  class PostingFbo < ApplicationRecord
    self.table_name = 'raw_ozon_postings_fbo'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
    has_many :posting_items, class_name: 'RawOzon::PostingItem',
             foreign_key: :posting_number, primary_key: :posting_number
    has_many :returns, class_name: 'RawOzon::Return',
             foreign_key: :posting_number, primary_key: :posting_number
  end
end
