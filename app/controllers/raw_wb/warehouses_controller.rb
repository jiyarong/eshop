module RawWb
  class WarehousesController < BaseController
    before_action :set_warehouse,  only: [:show, :update, :destroy]

    def index
      @warehouses = RawWb::Warehouse.all
      @warehouses = @warehouses.where(account_id: params[:account_id]) if params[:account_id].present?
      @warehouses = @warehouses.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @warehouse = RawWb::Warehouse.new(warehouse_params)
      @warehouse.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @warehouse.update!(warehouse_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @warehouse.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_warehouse
      @warehouse = RawWb::Warehouse.find(params[:id])
    end

    def warehouse_params
      params.require(:warehouse).permit!
    end
  end
end
