module RawWb
  class AdvCampaignDailyStat < ApplicationRecord
    self.table_name = "raw_wb_adv_campaign_daily_stats"

    belongs_to :campaign, class_name: "RawWb::AdvCampaign"
  end
end
