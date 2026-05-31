module RawWb
  class AccountBalance < ApplicationRecord
    self.table_name = 'raw_wb_account_balances'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
