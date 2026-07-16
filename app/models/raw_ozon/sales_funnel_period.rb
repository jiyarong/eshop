module RawOzon
  class SalesFunnelPeriod < ApplicationRecord
    self.table_name = "raw_ozon_sales_funnel_period"

    belongs_to :account, class_name: "RawOzon::SellerAccount"
  end
end
