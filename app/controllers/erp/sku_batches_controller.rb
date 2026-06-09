module Erp
  class SkuBatchesController < BaseController
    before_action :set_batch, only: [:show, :edit, :update]
    before_action -> { require_any_permission!(:manage_purchases, :manage_inventory) }, only: [:new, :create, :edit, :update]

    def index
      @batches = Ec::SkuBatch.includes(:sku).order(created_at: :desc)
    end

    def show
      @summary = Ec::BatchCostSummary.new(@batch).call
    end

    def new
      @batch = Ec::SkuBatch.new(status: "draft")
      @batch.sku_code = params[:sku_code] if params[:sku_code].present?
      load_sku_options
      render_modal_or_page(:new, :new_modal)
    end

    def edit
      load_sku_options
      render_modal_or_page(:edit, :edit_modal)
    end

    def create
      @batch = Ec::SkuBatch.new(batch_params)
      if @batch.save
        redirect_to erp_skus_path
      else
        load_sku_options
        render_modal_or_page(:new, :new_modal, status: :unprocessable_entity)
      end
    end

    def update
      if @batch.update(batch_params)
        redirect_to erp_skus_path
      else
        load_sku_options
        render_modal_or_page(:edit, :edit_modal, status: :unprocessable_entity)
      end
    end

    private

    def set_batch
      @batch = Ec::SkuBatch.includes(:sku, :cost_allocation_items).find(params[:id])
    end

    def load_sku_options
      @sku_options = Ec::Sku.order(:sku_code)
    end

    def batch_params
      params.require(:ec_sku_batch).permit(
        :sku_code,
        :batch_code,
        :status,
        :purchased_quantity,
        :received_quantity,
        :purchase_unit_price_cny,
        :expected_arrival_on,
        :received_on,
        :memo
      )
    end
  end
end
