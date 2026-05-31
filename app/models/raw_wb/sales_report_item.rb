module RawWb
  class SalesReportItem < ApplicationRecord
    self.table_name = 'raw_wb_sales_report_items'

    belongs_to :sales_report, class_name: 'RawWb::SalesReport'
    belongs_to :account,      class_name: 'RawWb::SellerAccount'
  end
end
