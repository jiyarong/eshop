module Ec
  class Snapshot < ApplicationRecord
    self.table_name = "ec_snapshots"

    TIME_ZONE = "Asia/Shanghai".freeze

    belongs_to :sku, class_name: "Ec::Sku", optional: true

    validates :snapshot_date, :snapshot_type, presence: true
    validates :snapshot_type, uniqueness: { scope: [ :snapshot_date, :sku_id ] }

    scope :of_type, ->(snapshot_type) { where(snapshot_type: snapshot_type.to_s) }
    scope :for_sku, ->(sku) { where(sku_id: sku.respond_to?(:id) ? sku.id : sku) }
    scope :global, -> { where(sku_id: nil) }
    scope :between, ->(from_date, to_date) { where(snapshot_date: from_date.to_date..to_date.to_date) }

    before_validation { self.snapshot_type = snapshot_type.to_s if snapshot_type.present? }

    def self.current_date
      Time.current.in_time_zone(TIME_ZONE).to_date
    end

    def self.fetch(snapshot_type, on: current_date, sku: nil)
      sku_id = sku.respond_to?(:id) ? sku.id : sku
      find_by!(snapshot_type: snapshot_type.to_s, snapshot_date: on.to_date, sku_id: sku_id).data
    end

    def data
      { value: content }.with_indifferent_access[:value]
    end
  end
end
