module RawWb
  class ProductsController < BaseController
    before_action :set_product,  only: [:show, :update, :destroy]

    def index
      @products = RawWb::Product.all
      @products = @products.where(account_id: params[:account_id]) if params[:account_id].present?
      @products = @products.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @product = RawWb::Product.new(product_params)
      @product.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @product.update!(product_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @product.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_product
      @product = RawWb::Product.find(params[:id])
    end

    def product_params
      params.require(:product).permit!
    end
  end
end
