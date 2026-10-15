module RawWb
  # Weekly catch-up of WB orders that left the active order feed. Their final status (sold, cancelled, ...) only
  # exists in the archive feed, so without this an order stays "new/waiting" after the 90 day status refresh stops.
  # BaseSync.run imports the orders touched by the run into ec_orders afterwards, which recomputes the
  # fulfillment business statuses.
  class ArchiveOrdersSync < BaseSync
    DEFAULT_DAYS = 1

    STEPS = %i[
      sync_recent_archive_orders
    ].freeze

    def self.run(days: nil, sync_keys: nil, wait: false)
      Time.use_zone("Europe/Moscow") do
        SyncRunLock.with_lock(OrderIncrementalSync::LOCK_NAME, wait: wait, logger: Rails.logger) do
          super(days: days, sync_keys: sync_keys)
        end
      end
    end
  end
end
