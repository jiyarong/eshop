module RawWb
  # Lightweight order-only sync intended for frequent scheduling.
  class OrderIncrementalSync < BaseSync
    DEFAULT_DAYS = 1
    LOCK_NAME = "raw_wb:daily_sync"

    STEPS = %i[
      sync_new_orders
      sync_orders
      sync_stats_orders
    ].freeze

    def self.run(days: nil, sync_keys: nil)
      SyncRunLock.with_lock(LOCK_NAME, wait: false, logger: Rails.logger) do
        super(days: days, sync_keys: sync_keys)
      end
    end
  end
end
