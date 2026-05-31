module RawWb
  class AdCampaign < ApplicationRecord
    self.table_name = 'raw_wb_ad_campaigns'

    belongs_to :account, class_name: 'RawWb::SellerAccount'

    has_many :ad_campaign_products, class_name: 'RawWb::AdCampaignProduct', foreign_key: :campaign_id, dependent: :destroy
    has_many :ad_keyword_bids,      class_name: 'RawWb::AdKeywordBid',      foreign_key: :campaign_id, dependent: :destroy
    has_many :ad_negative_keywords, class_name: 'RawWb::AdNegativeKeyword', foreign_key: :campaign_id, dependent: :destroy
    has_many :ad_daily_stats,       class_name: 'RawWb::AdDailyStat',       foreign_key: :campaign_id, dependent: :destroy
  end
end
