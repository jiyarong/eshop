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

      rows.sum { |row| persist_row(row) ? 1 : 0 }
    end

    private

    def persist_row(row)
      level = Ec::SkuInventoryLevel.new(row.merge(is_latest: true, created_at: @now, updated_at: @now))
      unless level.valid?
        Rails.logger.warn("[SkuInventorySnapshotSync] skipped invalid row #{row.inspect}: #{level.errors.full_messages.join(', ')}")
        return false
      end

      Ec::SkuInventoryLevel.transaction do
        latest_scope(row).update_all(is_latest: false, updated_at: @now)
        level.save!
      end
      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::InvalidForeignKey => e
      Rails.logger.warn("[SkuInventorySnapshotSync] failed row #{row.inspect}: #{e.class} #{e.message}")
      false
    end

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
        metadata: row[:metadata] || {},
        warehouse_breakdown: row[:warehouse_breakdown] || []
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
