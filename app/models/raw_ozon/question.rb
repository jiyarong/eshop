module RawOzon
  class Question < ApplicationRecord
    self.table_name = 'raw_ozon_questions'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
