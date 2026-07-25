module Ec
  class Snapshot < ApplicationRecord
    self.table_name = "ec_snapshots"

    TIME_ZONE = "Asia/Shanghai".freeze

    validates :snapshot_date, :snapshot_type, presence: true
    validates :snapshot_type, uniqueness: { scope: :snapshot_date }

    scope :of_type, ->(snapshot_type) { where(snapshot_type: snapshot_type.to_s) }
    scope :between, ->(from_date, to_date) { where(snapshot_date: from_date.to_date..to_date.to_date) }

    before_validation { self.snapshot_type = snapshot_type.to_s if snapshot_type.present? }

    def self.current_date
      Time.current.in_time_zone(TIME_ZONE).to_date
    end

    def self.fetch(snapshot_type, on: current_date)
      find_by!(snapshot_type: snapshot_type.to_s, snapshot_date: on.to_date).data
    end

    def data
      { value: content }.with_indifferent_access[:value]
    end
  end
end
