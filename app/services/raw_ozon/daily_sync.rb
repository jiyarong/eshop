module RawOzon
  # 每日两次（如 8:00 / 20:00）：同步交易类数据
  class DailySync < BaseSync
    DEFAULT_DAYS = 2

    STEPS = %i[
      sync_postings_fbs
      sync_postings_fbo
      sync_returns
      sync_product_prices
      sync_products
      sync_product_attributes
      sync_product_stocks
      sync_finance_transactions
      sync_finance_accrual_by_day
      sync_posting_destinations
      sync_supply_orders
    ].freeze

    def self.run(days: nil, sync_keys: nil)
      SyncRunLock.with_lock(OrderIncrementalSync::LOCK_NAME, wait: true, logger: Rails.logger) do
        super(days: days, sync_keys: sync_keys)
      end
    end
  end
end
