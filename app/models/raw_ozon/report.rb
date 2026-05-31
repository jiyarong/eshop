module RawOzon
  class Report < ApplicationRecord
    self.table_name = 'raw_ozon_reports'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
