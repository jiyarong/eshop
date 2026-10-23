module Ec
  class OwnWarehouseSkuCostAllocation < ApplicationRecord
    self.table_name = "ec_own_warehouse_sku_cost_allocations"
    belongs_to :sku, -> { with_deleted }, class_name: "Ec::Sku"
    belongs_to :own_warehouse_cost_period, class_name: "Ec::OwnWarehouseCostPeriod", optional: true
    validates :week_start, :week_end, :allocation_version, presence: true
    scope :current, -> { where(is_current: true) }
    scope :for_week, ->(date) { where(week_start: date.to_date.beginning_of_week(:monday)) }
  end
end
