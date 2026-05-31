module RawWb
  class StocksController < BaseController
    before_action :set_stock,  only: [:show, :update, :destroy]

    def index
      @stocks = RawWb::Stock.all
      @stocks = @stocks.where(account_id: params[:account_id]) if params[:account_id].present?
      @stocks = @stocks.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @stock = RawWb::Stock.new(stock_params)
      @stock.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @stock.update!(stock_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @stock.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_stock
      @stock = RawWb::Stock.find(params[:id])
    end

    def stock_params
      params.require(:stock).permit!
    end
  end
end
