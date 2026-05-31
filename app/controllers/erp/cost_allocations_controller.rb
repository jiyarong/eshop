module Erp
  class CostAllocationsController < BaseController
    def index
      @cost_allocations = Ec::CostAllocation.order(created_at: :desc)
    end

    def show
      @cost_allocation = Ec::CostAllocation.includes(items: { sku_batch: :sku }).find(params[:id])
    end
  end
end
