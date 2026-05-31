module RawOzon
  class PerformanceSkuSpend < ApplicationRecord
    self.table_name = 'raw_ozon_performance_sku_spends'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'

    scope :ppc,       -> { where(ad_type: 'ppc') }
    scope :promotion, -> { where(ad_type: 'promotion') }
    scope :for_period, ->(from, to) { where(period_from: from, period_to: to) }
  end
end
