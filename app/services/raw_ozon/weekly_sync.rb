module RawOzon
  # 每周一次（如周一凌晨）：同步分析、报表、商品目录等低频数据
  class WeeklySync < BaseSync
    DEFAULT_DAYS = 7

    STEPS = %i[
      sync_products
      sync_analytics
      sync_analytics_stocks
      sync_promotions
      sync_finance_realization
    ].freeze
  end
end
