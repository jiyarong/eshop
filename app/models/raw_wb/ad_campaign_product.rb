module RawWb
  class AdCampaignProduct < ApplicationRecord
    self.table_name = 'raw_wb_ad_campaign_products'

    belongs_to :campaign, class_name: 'RawWb::AdCampaign'
  end
end
