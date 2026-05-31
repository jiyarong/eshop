module RawWb
  class StatsSale < ApplicationRecord
    self.table_name = 'raw_wb_stats_sales'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
