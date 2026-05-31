module RawOzon
  class PerformanceCampaignSku < ApplicationRecord
    self.table_name = "raw_ozon_performance_campaign_skus"

    belongs_to :campaign, class_name: "RawOzon::PerformanceCampaign"
  end
end
