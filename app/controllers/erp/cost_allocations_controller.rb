module Erp
  class CostAllocationsController < BaseController
    before_action :set_cost_allocation, only: [:show, :edit, :update]
    before_action -> { require_permission!(:manage_finance) }, only: [:new, :create, :edit, :update]

    def index
      @cost_allocations = Ec::CostAllocation.order(created_at: :desc)
    end

    def show
    end

    def new
      @cost_allocation = Ec::CostAllocation.new(
        cost_type: "international_freight",
        allocation_method: "manual",
        status: "draft"
      )
      build_blank_items
      load_batch_options
    end

    def edit
      build_blank_items
      load_batch_options
    end

    def create
      @cost_allocation = Ec::CostAllocation.new(cost_allocation_params)
      if @cost_allocation.save
        redirect_to erp_cost_allocation_path(@cost_allocation)
      else
        build_blank_items
        load_batch_options
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @cost_allocation.update(cost_allocation_params)
        redirect_to erp_cost_allocation_path(@cost_allocation)
      else
        build_blank_items
        load_batch_options
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_cost_allocation
      @cost_allocation = Ec::CostAllocation.includes(items: { sku_batch: :sku }).find(params[:id])
    end

    def build_blank_items
      (3 - @cost_allocation.items.size).times { @cost_allocation.items.build }
    end

    def load_batch_options
      @batch_options = Ec::SkuBatch.includes(:sku).order(created_at: :desc)
    end

    def cost_allocation_params
      params.require(:ec_cost_allocation).permit(
        :allocation_no,
        :cost_type,
        :allocation_method,
        :total_amount_cny,
        :allocated_on,
        :status,
        :memo,
        items_attributes: [:id, :sku_batch_id, :amount_cny, :memo]
      )
    end
  end
end
