module RawWb
  class ReturnClaim < ApplicationRecord
    self.table_name = 'raw_wb_return_claims'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
    belongs_to :order,   class_name: 'RawWb::Order', optional: true
  end
end
