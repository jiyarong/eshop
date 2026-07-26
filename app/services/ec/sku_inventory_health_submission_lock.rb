module Ec
  class SkuInventoryHealthSubmissionLock
    TTL = 5.seconds

    def self.acquire(sku_id)
      Rails.cache.write(
        "ec:sku_inventory_health_submission:#{sku_id}",
        true,
        expires_in: TTL,
        unless_exist: true
      )
    end
  end
end
