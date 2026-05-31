module RawWb
  class FbsStock < ApplicationRecord
    self.table_name = 'raw_wb_fbs_stocks'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
