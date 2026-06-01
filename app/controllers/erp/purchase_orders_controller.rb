module Erp
  class PurchaseOrdersController < BaseController
    before_action :set_purchase_order, only: [:show, :edit, :update]
    before_action -> { require_permission!(:manage_purchases) }, only: [:new, :create, :edit, :update]

    def index
      @purchase_orders = Ec::PurchaseOrder.includes(:supplier).order(created_at: :desc)
    end

    def show
    end

    def new
      @purchase_order = Ec::PurchaseOrder.new(status: "draft", currency: "CNY")
      build_blank_items
      load_form_options
    end

    def edit
      build_blank_items
      load_form_options
    end

    def create
      @purchase_order = Ec::PurchaseOrder.new(purchase_order_params)
      if @purchase_order.save
        redirect_to erp_purchase_order_path(@purchase_order)
      else
        build_blank_items
        load_form_options
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @purchase_order.update(purchase_order_params)
        redirect_to erp_purchase_order_path(@purchase_order)
      else
        build_blank_items
        load_form_options
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_purchase_order
      @purchase_order = Ec::PurchaseOrder.includes(:supplier, items: [:sku, :sku_batch]).find(params[:id])
    end

    def build_blank_items
      (3 - @purchase_order.items.size).times { @purchase_order.items.build }
    end

    def load_form_options
      @supplier_options = Ec::Supplier.active.order(:name)
      @batch_options = Ec::SkuBatch.includes(:sku).order(created_at: :desc)
    end

    def purchase_order_params
      params.require(:ec_purchase_order).permit(
        :order_no,
        :supplier_id,
        :ordered_on,
        :status,
        :currency,
        :memo,
        items_attributes: [:id, :sku_batch_id, :quantity, :unit_price_cny, :memo]
      )
    end
  end
end
