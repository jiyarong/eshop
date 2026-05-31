module RawOzon
  class Analytics < ApplicationRecord
    self.table_name = 'raw_ozon_analytics'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
