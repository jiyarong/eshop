module RawOzon
  class AdDailyStat < ApplicationRecord
    self.table_name = "raw_ozon_ad_daily_stats"

    belongs_to :account, class_name: "RawOzon::SellerAccount"
    belongs_to :ad_unit, class_name: "RawOzon::AdUnit"

    validates :stat_date, :cost_model, :synced_at, presence: true
  end
end
