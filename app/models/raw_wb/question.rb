module RawWb
  class Question < ApplicationRecord
    self.table_name = 'raw_wb_questions'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
