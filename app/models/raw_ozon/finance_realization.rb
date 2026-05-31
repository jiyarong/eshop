module RawOzon
  class FinanceRealization < ApplicationRecord
    self.table_name = 'raw_ozon_finance_realizations'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
