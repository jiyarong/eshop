module Ec
  class CostAllocationItem < ApplicationRecord
    self.table_name = "ec_cost_allocation_items"

    belongs_to :cost_allocation, class_name: "Ec::CostAllocation"
    belongs_to :sku_batch, class_name: "Ec::SkuBatch"

    validates :amount_cny, numericality: { greater_than_or_equal_to: 0 }
    validates :sku_batch_id, uniqueness: { scope: :cost_allocation_id }
  end
end
