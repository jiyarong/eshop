module Erp
  class SuppliersController < BaseController
    def index
      @suppliers = Ec::Supplier.order(:name)
    end

    def show
      @supplier = Ec::Supplier.find(params[:id])
      @purchase_orders = @supplier.purchase_orders.order(created_at: :desc)
    end
  end
end
