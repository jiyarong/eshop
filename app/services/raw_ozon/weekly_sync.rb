module RawOzon
  # 每周一次（如周一凌晨）：同步分析、报表、商品目录等低频数据
  class WeeklySync < BaseSync
    DEFAULT_DAYS = 7

    STEPS = %i[
      sync_products
      sync_product_attributes
      sync_promotions
      sync_finance_realization
      sync_product_queries
      sync_product_queries_through_friday
    ].freeze
  end
end
