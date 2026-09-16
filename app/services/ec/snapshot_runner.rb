module Ec
  class SnapshotRunner
    # .capture must return rows shaped as { sku_id: nil, content: ... }.
    SNAPSHOT_MODULES = [ Ec::InventorySnapshot, Ec::SkuContextSnapshot ].freeze

    def self.run(snapshot_date: nil)
      new(snapshot_date: snapshot_date).run
    end

    def initialize(snapshot_date: nil, modules: SNAPSHOT_MODULES)
      @snapshot_date = (snapshot_date || Ec::Snapshot.current_date).to_date
      @modules = modules
    end

    def run
      @modules.sum do |snapshot_module|
        rows = build_rows(snapshot_module)
        persist_rows(rows)
        prune_expired_snapshots(snapshot_module)
        rows.size
      end
    end

    private

    def build_rows(snapshot_module)
      Array.wrap(snapshot_module.capture(snapshot_date: @snapshot_date)).map do |captured_row|
        captured_row = captured_row.to_h.symbolize_keys
        {
          snapshot_date: @snapshot_date,
          snapshot_type: snapshot_module.snapshot_type.to_s,
          sku_id: captured_row[:sku_id],
          content: captured_row.fetch(:content)
        }
      end
    end

    def upsert_rows(rows, unique_by:)
      return if rows.empty?

      Ec::Snapshot.upsert_all(rows, unique_by: unique_by, record_timestamps: false)
    end

    def persist_rows(rows)
      global_rows, sku_rows = rows.partition { |row| row[:sku_id].nil? }
      upsert_rows(global_rows, unique_by: :idx_ec_snapshots_global_unique)
      upsert_rows(sku_rows, unique_by: :idx_ec_snapshots_sku_daily_unique)
    end

    def prune_expired_snapshots(snapshot_module)
      return unless snapshot_module.respond_to?(:retention_days)

      retention_days = snapshot_module.retention_days.to_i
      return unless retention_days.positive?

      snapshots = Ec::Snapshot.of_type(snapshot_module.snapshot_type)
      latest_date = snapshots.maximum(:snapshot_date)
      return unless latest_date

      snapshots.where(snapshot_date: ...(latest_date - (retention_days - 1).days)).delete_all
    end
  end
end
