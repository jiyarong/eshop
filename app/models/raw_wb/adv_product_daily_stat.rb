module RawWb
  class AdvProductDailyStat < ApplicationRecord
    self.table_name = "raw_wb_adv_product_daily_stats"

    belongs_to :campaign, class_name: "RawWb::AdvCampaign"

    scope :all_apps, -> { where(app_type: -1) }
  end
end
