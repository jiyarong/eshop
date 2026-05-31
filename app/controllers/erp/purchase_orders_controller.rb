module Erp
  class PurchaseOrdersController < BaseController
    def index
      @purchase_orders = Ec::PurchaseOrder.includes(:supplier).order(created_at: :desc)
    end

    def show
      @purchase_order = Ec::PurchaseOrder.includes(:supplier, items: [:sku, :sku_batch]).find(params[:id])
    end
  end
end
