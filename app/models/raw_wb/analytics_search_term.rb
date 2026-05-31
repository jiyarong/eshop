module RawWb
  class AnalyticsSearchTerm < ApplicationRecord
    self.table_name = 'raw_wb_analytics_search_terms'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
