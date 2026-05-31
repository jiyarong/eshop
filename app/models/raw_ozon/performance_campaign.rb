module RawOzon
  class PerformanceCampaign < ApplicationRecord
    self.table_name = "raw_ozon_performance_campaigns"

    belongs_to :account, class_name: "RawOzon::SellerAccount"
    has_many :campaign_skus, class_name: "RawOzon::PerformanceCampaignSku", foreign_key: :campaign_id, dependent: :destroy
    has_many :daily_stats, class_name: "RawOzon::PerformanceDailyStat", foreign_key: :campaign_id, dependent: :destroy

    scope :running,  -> { where(state: "CAMPAIGN_STATE_RUNNING") }
    scope :sku_type, -> { where(adv_object_type: "SKU") }
    scope :search_promo, -> { where(adv_object_type: "SEARCH_PROMO") }
  end
end
