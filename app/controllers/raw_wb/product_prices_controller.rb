module RawWb
  class ProductPricesController < BaseController
    before_action :set_product_price,  only: [:show, :update, :destroy]

    def index
      @product_prices = RawWb::ProductPrice.all
      @product_prices = @product_prices.where(account_id: params[:account_id]) if params[:account_id].present?
      @product_prices = @product_prices.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @product_price = RawWb::ProductPrice.new(product_price_params)
      @product_price.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @product_price.update!(product_price_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @product_price.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_product_price
      @product_price = RawWb::ProductPrice.find(params[:id])
    end

    def product_price_params
      params.require(:product_price).permit!
    end
  end
end
