module RawWb
  class ProductSkusController < BaseController
    before_action :set_product_sku,  only: [:show, :update, :destroy]

    def index
      @product_skus = RawWb::ProductSku.all
      @product_skus = @product_skus.where(account_id: params[:account_id]) if params[:account_id].present?
      @product_skus = @product_skus.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @product_sku = RawWb::ProductSku.new(product_sku_params)
      @product_sku.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @product_sku.update!(product_sku_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @product_sku.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_product_sku
      @product_sku = RawWb::ProductSku.find(params[:id])
    end

    def product_sku_params
      params.require(:product_sku).permit!
    end
  end
end
