module Ec
  class SkuInventoryLevelRetention
    RETENTION_PERIOD = 35.days
    BATCH_SIZE = 10_000

    def self.run(now: Time.current)
      new(now: now).run
    end

    def initialize(now: Time.current)
      @now = now
    end

    def run
      expired_levels.in_batches(of: BATCH_SIZE).delete_all
    end

    private

    def expired_levels
      Ec::SkuInventoryLevel.where(is_latest: false, synced_at: ...(@now - RETENTION_PERIOD))
    end
  end
end
