module RawWb
  class AnalyticsSalesFunnel < ApplicationRecord
    self.table_name = 'raw_wb_analytics_sales_funnels'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
