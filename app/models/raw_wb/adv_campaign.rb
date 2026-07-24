module RawWb
  class AdvCampaign < ApplicationRecord
    self.table_name = "raw_wb_adv_campaigns"

    belongs_to :store, class_name: "Ec::Store"
    has_many :products, class_name: "RawWb::AdvCampaignProduct", foreign_key: :campaign_id, dependent: :destroy
    has_many :budget_snapshots, class_name: "RawWb::AdvBudgetSnapshot", foreign_key: :campaign_id, dependent: :destroy
    has_many :daily_stats, class_name: "RawWb::AdvCampaignDailyStat", foreign_key: :campaign_id, dependent: :destroy
    has_many :product_daily_stats, class_name: "RawWb::AdvProductDailyStat", foreign_key: :campaign_id, dependent: :destroy
  end
end
