module RawOzon
  class AdReportRun < ApplicationRecord
    self.table_name = "raw_ozon_ad_report_runs"

    belongs_to :account, class_name: "RawOzon::SellerAccount"

    validates :report_type, :endpoint, :period_from, :period_to, :state, presence: true
  end
end
