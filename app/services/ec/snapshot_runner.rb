module Ec
  class SnapshotRunner
    # A module must expose .snapshot_type and .capture(snapshot_date:).
    SNAPSHOT_MODULES = [].freeze

    def self.run(snapshot_date: nil)
      new(snapshot_date: snapshot_date).run
    end

    def initialize(snapshot_date: nil, modules: SNAPSHOT_MODULES)
      @snapshot_date = (snapshot_date || Ec::Snapshot.current_date).to_date
      @modules = modules
    end

    def run
      rows = @modules.map { |snapshot_module| build_row(snapshot_module) }
      return 0 if rows.empty?

      Ec::Snapshot.upsert_all(
        rows,
        unique_by: [ :snapshot_type, :snapshot_date ],
        record_timestamps: false
      )

      rows.size
    end

    private

    def build_row(snapshot_module)
      {
        snapshot_date: @snapshot_date,
        snapshot_type: snapshot_module.snapshot_type.to_s,
        content: snapshot_module.capture(snapshot_date: @snapshot_date)
      }
    end
  end
end
