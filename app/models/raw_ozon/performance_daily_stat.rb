module RawOzon
  class PerformanceDailyStat < ApplicationRecord
    self.table_name = "raw_ozon_performance_daily_stats"

    belongs_to :account,  class_name: "RawOzon::SellerAccount"
    belongs_to :campaign, class_name: "RawOzon::PerformanceCampaign"

    scope :in_range, ->(from, to) { where(stat_date: from..to) }
  end
end
