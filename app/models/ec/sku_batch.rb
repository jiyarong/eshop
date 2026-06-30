module Ec
  class SkuBatch < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_sku_batches"

    STATUSES = %w[draft ordered in_transit received closed].freeze

    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code
    has_many :cost_allocation_items, class_name: "Ec::CostAllocationItem", foreign_key: :sku_batch_id

    validates :sku_code, :batch_code, presence: true
    validates :batch_code, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validates :purchased_quantity, :received_quantity, numericality: { greater_than_or_equal_to: 0 }
    validates :purchase_unit_price_cny, numericality: { greater_than_or_equal_to: 0 }

    before_validation do
      self.sku_code = sku_code&.upcase
      self.batch_code = batch_code&.strip&.upcase
    end

    def costing_quantity
      received_quantity.positive? ? received_quantity : purchased_quantity
    end
  end
end
