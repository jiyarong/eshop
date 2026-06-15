module RawOzon
  # Lightweight order-only sync intended for frequent scheduling.
  class OrderIncrementalSync < BaseSync
    DEFAULT_DAYS = 2
    LOCK_NAME = "raw_ozon:daily_sync"

    STEPS = %i[
      sync_postings_fbs
      sync_postings_fbo
    ].freeze

    def self.run(days: nil, sync_keys: nil)
      SyncRunLock.with_lock(LOCK_NAME, wait: false, logger: Rails.logger) do
        super(days: days, sync_keys: sync_keys)
      end
    end
  end
end
