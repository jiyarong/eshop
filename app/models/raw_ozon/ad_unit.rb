module RawOzon
  class AdUnit < ApplicationRecord
    self.table_name = "raw_ozon_ad_units"
    STATES = %w[CAMPAIGN_STATE_RUNNING CAMPAIGN_STATE_INACTIVE CAMPAIGN_STATE_ARCHIVED].freeze

    belongs_to :account, class_name: "RawOzon::SellerAccount"
    has_many :products, class_name: "RawOzon::AdUnitProduct", dependent: :destroy
    has_many :daily_stats, class_name: "RawOzon::AdDailyStat", dependent: :destroy
    has_many :sku_daily_stats, class_name: "RawOzon::AdSkuDailyStat", dependent: :destroy

    validates :external_id, :unit_type, :synced_at, presence: true
  end
end
