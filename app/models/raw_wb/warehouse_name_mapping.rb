module RawWb
  class WarehouseNameMapping < ApplicationRecord
    self.table_name = "raw_wb_warehouse_name_mappings"

    STATUSES = %w[verified candidate rejected retired].freeze

    belongs_to :account, class_name: "RawWb::SellerAccount", optional: true
    belongs_to :verified_by, class_name: "User", optional: true

    validates :historical_name, :normalized_historical_name, :warehouse_id,
      :canonical_name, :region_name, :mapping_source, :confidence, :status, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validate :valid_date_order

    before_validation :normalize_historical_name

    scope :verified, -> { where(status: "verified") }
    scope :effective_on, ->(date) {
      where("valid_from IS NULL OR valid_from <= ?", date)
        .where("valid_to IS NULL OR valid_to >= ?", date)
    }

    private

    def normalize_historical_name
      self.normalized_historical_name = RawWb::WarehouseRegion.normalize_warehouse_name(historical_name)
    end

    def valid_date_order
      return if valid_from.blank? || valid_to.blank? || valid_to >= valid_from

      errors.add(:valid_to, :greater_than_or_equal_to, count: valid_from)
    end
  end
end
