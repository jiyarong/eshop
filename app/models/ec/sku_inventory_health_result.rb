module Ec
  class SkuInventoryHealthResult < ApplicationRecord
    self.table_name = "ec_sku_inventory_health_results"

    belongs_to :sku, class_name: "Ec::Sku"
    belongs_to :submitted_by, class_name: "User"

    validates :events, presence: true
    validate :events_must_be_an_array

    scope :recent_first, -> { order(created_at: :desc, id: :desc) }

    def self.latest_for_sku_ids(sku_ids)
      where(sku_id: sku_ids)
        .select("DISTINCT ON (sku_id) ec_sku_inventory_health_results.*")
        .order(:sku_id, created_at: :desc, id: :desc)
        .index_by(&:sku_id)
    end

    private

    def events_must_be_an_array
      errors.add(:events, :invalid) unless events.is_a?(Array)
    end
  end
end
