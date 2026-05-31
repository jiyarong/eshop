module RawWb
  class PromotionsController < BaseController
    before_action :set_promotion,  only: [:show, :update, :destroy]

    def index
      @promotions = RawWb::Promotion.all
      @promotions = @promotions.where(account_id: params[:account_id]) if params[:account_id].present?
      @promotions = @promotions.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @promotion = RawWb::Promotion.new(promotion_params)
      @promotion.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @promotion.update!(promotion_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @promotion.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_promotion
      @promotion = RawWb::Promotion.find(params[:id])
    end

    def promotion_params
      params.require(:promotion).permit!
    end
  end
end
