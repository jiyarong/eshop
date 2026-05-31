module RawWb
  class AdKeywordBid < ApplicationRecord
    self.table_name = 'raw_wb_ad_keyword_bids'

    belongs_to :campaign, class_name: 'RawWb::AdCampaign'
  end
end
