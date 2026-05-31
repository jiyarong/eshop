module RawWb
  class AdSkuSpend < ApplicationRecord
    self.table_name = 'raw_wb_ad_sku_spends'

    belongs_to :campaign, class_name: 'RawWb::AdCampaign'
  end
end
