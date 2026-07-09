module RawWb
  class CategoriesController < BaseController
    before_action :set_category,  only: [:show, :update, :destroy]

    def index
      @categories = RawWb::Category.all
      @categories = @categories.where(account_id: params[:account_id]) if params[:account_id].present?
      @categories = @categories.page(params[:page]).per(params[:per_page] || 20)
    end

    def tree
      @categories = RawWb::Category.includes(:subjects).order(:name)
    end

    def show; end

    def create
      @category = RawWb::Category.new(category_params)
      @category.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @category.update!(category_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @category.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_category
      @category = RawWb::Category.find(params[:id])
    end

    def category_params
      params.require(:category).permit!
    end
  end
end
