module Erp
  class SkuBatchesController < BaseController
    def index
      @batches = Ec::SkuBatch.includes(:sku).order(created_at: :desc)
    end

    def show
      @batch = Ec::SkuBatch.includes(:sku, :cost_allocation_items).find(params[:id])
      @summary = Ec::BatchCostSummary.new(@batch).call
    end
  end
end
