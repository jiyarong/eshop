module Ec
  class SkuInventorySnapshotSync
    def self.run
      new.run
    end

    def initialize(snapshot_fetcher: nil, now: Time.current)
      @snapshot_fetcher = snapshot_fetcher || -> { Ec::SkuInventorySnapshotFetcher.new.call(now: now) }
      @now = now
    end

    def run
      rows = Array(@snapshot_fetcher.call).map { |row| normalize_row(row) }
      return 0 if rows.empty?

      Ec::SkuInventoryLevel.transaction do
        rows.each do |row|
          latest_scope(row).update_all(is_latest: false, updated_at: @now)
          Ec::SkuInventoryLevel.create!(row.merge(is_latest: true, created_at: @now, updated_at: @now))
        end
      end

      rows.size
    end

    private

    def normalize_row(row)
      row = row.symbolize_keys
      {
        sku_code: row.fetch(:sku_code).to_s.upcase,
        platform: row.fetch(:platform).to_s,
        account_id: row.fetch(:account_id),
        store_id: row[:store_id],
        store_name: row[:store_name],
        fulfillment_type: row.fetch(:fulfillment_type).to_s,
        quantity: row.fetch(:quantity).to_i,
        synced_at: row[:synced_at] || @now,
        metadata: row[:metadata] || {}
      }
    end

    def latest_scope(row)
      Ec::SkuInventoryLevel.latest.where(
        sku_code: row[:sku_code],
        platform: row[:platform],
        account_id: row[:account_id],
        fulfillment_type: row[:fulfillment_type]
      )
    end
  end
end
