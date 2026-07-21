module RawWb
  class SalesFunnelDaily < ApplicationRecord
    self.table_name = "raw_wb_sales_funnel_daily"

    belongs_to :account, class_name: "RawWb::SellerAccount"
  end
end
