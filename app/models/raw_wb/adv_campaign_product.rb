module RawWb
  class AdvCampaignProduct < ApplicationRecord
    self.table_name = "raw_wb_adv_campaign_products"

    belongs_to :campaign, class_name: "RawWb::AdvCampaign"
  end
end
