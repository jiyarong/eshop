module RawWb
  class SalesReport < ApplicationRecord
    self.table_name = 'raw_wb_sales_reports'

    belongs_to :account, class_name: 'RawWb::SellerAccount'

    has_many :sales_report_items, class_name: 'RawWb::SalesReportItem', foreign_key: :sales_report_id, dependent: :destroy
  end
end
