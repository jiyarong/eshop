module Erp
  class SkuCategoriesController < BaseController
    before_action :set_category, only: [:show, :edit, :update]

    def index
      @categories = Ec::SkuCategory.includes(:parent).order(:position, :code)
    end

    def show
      @children = @category.children.order(:position, :code)
    end

    def new
      @category = Ec::SkuCategory.new
      load_parent_options
    end

    def edit
      load_parent_options
    end

    def create
      @category = Ec::SkuCategory.new(category_params)
      if @category.save
        redirect_to erp_sku_category_path(@category)
      else
        load_parent_options
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @category.update(category_params)
        redirect_to erp_sku_category_path(@category)
      else
        load_parent_options
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_category
      @category = Ec::SkuCategory.find(params[:id])
    end

    def load_parent_options
      @parent_options = Ec::SkuCategory.order(:position, :code)
      @parent_options = @parent_options.where.not(id: @category.id) if @category.persisted?
    end

    def category_params
      params.require(:ec_sku_category).permit(:code, :name, :parent_id, :position, :is_active, :memo)
    end
  end
end
