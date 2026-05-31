module RawWb
  class AdDailyStat < ApplicationRecord
    self.table_name = 'raw_wb_ad_daily_stats'

    belongs_to :campaign, class_name: 'RawWb::AdCampaign'
  end
end
