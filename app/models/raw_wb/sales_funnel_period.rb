module RawWb
  class SalesFunnelPeriod < ApplicationRecord
    self.table_name = "raw_wb_sales_funnel_period"

    belongs_to :account, class_name: "RawWb::SellerAccount"
  end
end
