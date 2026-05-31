module RawWb
  class SuppliesController < BaseController
    before_action :set_supply,  only: [:show, :update, :destroy]

    def index
      @supplies = RawWb::Supply.all
      @supplies = @supplies.where(account_id: params[:account_id]) if params[:account_id].present?
      @supplies = @supplies.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @supply = RawWb::Supply.new(supply_params)
      @supply.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @supply.update!(supply_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @supply.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_supply
      @supply = RawWb::Supply.find(params[:id])
    end

    def supply_params
      params.require(:supply).permit!
    end
  end
end
