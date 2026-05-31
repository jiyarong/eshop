module RawWb
  class AdNegativeKeyword < ApplicationRecord
    self.table_name = 'raw_wb_ad_negative_keywords'

    belongs_to :campaign, class_name: 'RawWb::AdCampaign'
  end
end
