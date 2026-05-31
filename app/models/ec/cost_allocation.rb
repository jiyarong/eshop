module Ec
  class CostAllocation < ApplicationRecord
    self.table_name = "ec_cost_allocations"

    COST_TYPES = %w[international_freight customs certification warehouse misc].freeze
    ALLOCATION_METHODS = %w[manual by_quantity by_purchase_amount].freeze
    STATUSES = %w[draft locked].freeze

    has_many :items, class_name: "Ec::CostAllocationItem", foreign_key: :cost_allocation_id, dependent: :destroy

    validates :allocation_no, presence: true, uniqueness: true
    validates :cost_type, inclusion: { in: COST_TYPES }
    validates :allocation_method, inclusion: { in: ALLOCATION_METHODS }
    validates :status, inclusion: { in: STATUSES }
    validates :total_amount_cny, numericality: { greater_than: 0 }
    validate :locked_items_total_matches_total_amount

    before_validation { self.allocation_no = allocation_no&.strip&.upcase }

    def allocated_amount_cny
      items.sum { |item| item.amount_cny.to_d }
    end

    private

    def locked_items_total_matches_total_amount
      return unless status == "locked"
      return if allocated_amount_cny == total_amount_cny.to_d

      errors.add(:base, "分摊明细合计必须等于费用总额")
    end
  end
end
