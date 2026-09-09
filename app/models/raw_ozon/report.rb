module RawOzon
  class Report < ApplicationRecord
    self.table_name = 'raw_ozon_reports'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
    has_many :posting_report_items, class_name: "RawOzon::PostingReportItem", foreign_key: :report_id, dependent: :nullify
  end
end
