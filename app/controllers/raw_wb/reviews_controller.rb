module RawWb
  class ReviewsController < BaseController
    before_action :set_review,  only: [:show, :update, :destroy]

    def index
      @reviews = RawWb::Review.all
      @reviews = @reviews.where(account_id: params[:account_id]) if params[:account_id].present?
      @reviews = @reviews.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @review = RawWb::Review.new(review_params)
      @review.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @review.update!(review_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @review.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_review
      @review = RawWb::Review.find(params[:id])
    end

    def review_params
      params.require(:review).permit!
    end
  end
end
