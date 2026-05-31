module RawOzon
  class FinanceTransaction < ApplicationRecord
    self.table_name = 'raw_ozon_finance_transactions'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
