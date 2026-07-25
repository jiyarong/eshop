module Ec
  class SnapshotRunner
    # .capture must return rows shaped as { sku_id: nil, content: ... }.
    SNAPSHOT_MODULES = [].freeze

    def self.run(snapshot_date: nil)
      new(snapshot_date: snapshot_date).run
    end

    def initialize(snapshot_date: nil, modules: SNAPSHOT_MODULES)
      @snapshot_date = (snapshot_date || Ec::Snapshot.current_date).to_date
      @modules = modules
    end

    def run
      rows = @modules.flat_map { |snapshot_module| build_rows(snapshot_module) }
      return 0 if rows.empty?

      global_rows, sku_rows = rows.partition { |row| row[:sku_id].nil? }
      upsert_rows(global_rows, unique_by: :idx_ec_snapshots_global_unique)
      upsert_rows(sku_rows, unique_by: :idx_ec_snapshots_sku_daily_unique)

      rows.size
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
  end
end
