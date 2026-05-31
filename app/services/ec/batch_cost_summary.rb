module Ec
  class BatchCostSummary
    def initialize(batch)
      @batch = batch
    end

    def call
      {
        batch: batch,
        purchase_cost_cny: purchase_cost_cny,
        allocated_cost_cny: allocated_cost_cny,
        total_cost_cny: total_cost_cny,
        unit_cost_cny: unit_cost_cny
      }
    end

    private

    attr_reader :batch

    def quantity
      batch.costing_quantity.to_i
    end

    def purchase_cost_cny
      batch.purchase_unit_price_cny.to_d * quantity
    end

    def allocated_cost_cny
      batch.cost_allocation_items.joins(:cost_allocation)
           .where(ec_cost_allocations: { status: "locked" })
           .sum(:amount_cny)
           .to_d
    end

    def total_cost_cny
      purchase_cost_cny + allocated_cost_cny
    end

    def unit_cost_cny
      return 0.to_d if quantity.zero?

      (total_cost_cny / quantity).round(4)
    end
  end
end
