module RawWb
  class OrdersController < BaseController
    before_action :set_order,  only: [:show, :update, :destroy]

    def index
      @orders = RawWb::Order.all
      @orders = @orders.where(account_id: params[:account_id]) if params[:account_id].present?
      @orders = @orders.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @order = RawWb::Order.new(order_params)
      @order.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @order.update!(order_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @order.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_order
      @order = RawWb::Order.find(params[:id])
    end

    def order_params
      params.require(:order).permit!
    end
  end
end
