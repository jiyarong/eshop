module Ec
  class SkuContextSnapshotFetcher
    def self.fetch(sku, snapshot_date: nil)
      new(sku: sku, snapshot_date: snapshot_date).call
    end

    def initialize(
      sku:,
      snapshot_date: nil,
      snapshot_builder: Ec::SkuContextSnapshot,
      lock: SyncRunLock
    )
      if sku.is_a?(String)
        sku = Ec::Sku.find_by(sku_code: sku)
      end
      @sku = sku
      @snapshot_date = (snapshot_date || Ec::Snapshot.current_date).to_date
      @snapshot_builder = snapshot_builder
      @lock = lock
    end

    def call
      snapshot = snapshot_for_date
      return snapshot.data if snapshot

      lock.with_lock(lock_name, wait: true, logger: Rails.logger) do
        (snapshot_for_date || create_snapshot).data
      end
    end

    private

    attr_reader :sku, :snapshot_date, :snapshot_builder, :lock

    def snapshot_for_date
      Ec::Snapshot.find_by(
        snapshot_type: snapshot_builder.snapshot_type,
        snapshot_date: snapshot_date,
        sku_id: sku.id
      )
    end

    def create_snapshot
      captured_row = snapshot_builder.capture_for(sku: sku, snapshot_date: snapshot_date)
      Ec::Snapshot.upsert_all(
        [
          {
            snapshot_type: snapshot_builder.snapshot_type,
            snapshot_date: snapshot_date,
            sku_id: captured_row.fetch(:sku_id),
            content: captured_row.fetch(:content)
          }
        ],
        unique_by: :idx_ec_snapshots_sku_daily_unique,
        record_timestamps: false
      )
      prune_expired_snapshots
      snapshot_for_date || raise(ActiveRecord::RecordNotFound)
    end

    def prune_expired_snapshots
      snapshots = Ec::Snapshot.of_type(snapshot_builder.snapshot_type)
      latest_date = snapshots.maximum(:snapshot_date)
      return unless latest_date

      cutoff = latest_date - (snapshot_builder.retention_days - 1).days
      snapshots.where(snapshot_date: ...cutoff).delete_all
    end

    def lock_name
      "ec:sku_context_snapshot:#{sku.id}:#{snapshot_date.iso8601}"
    end
  end
end
