module RawOzon
  class SalesFunnelDaily < ApplicationRecord
    self.table_name = "raw_ozon_sales_funnel_daily"

    belongs_to :account, class_name: "RawOzon::SellerAccount"
  end
end
