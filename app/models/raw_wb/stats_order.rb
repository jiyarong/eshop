module RawWb
  class StatsOrder < ApplicationRecord
    self.table_name = 'raw_wb_stats_orders'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
