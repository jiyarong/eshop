module RawOzon
  class AnalyticsStock < ApplicationRecord
    self.table_name = 'raw_ozon_analytics_stocks'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
