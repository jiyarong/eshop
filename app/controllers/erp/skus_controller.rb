module Erp
  class SkusController < BaseController
    before_action :set_sku, only: [:show, :edit, :update]
    before_action -> { require_permission!(:manage_skus) }, only: [:new, :create, :edit, :update]

    def index
      @skus = Ec::Sku.includes(:sku_category).order(:sku_code)
    end

    def show
    end

    def new
      @sku = Ec::Sku.new(is_active: true)
      load_category_options
    end

    def edit
      load_category_options
    end

    def create
      @sku = Ec::Sku.new(sku_params)
      if @sku.save
        redirect_to erp_sku_path(@sku)
      else
        load_category_options
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @sku.update(sku_params)
        redirect_to erp_sku_path(@sku)
      else
        load_category_options
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_sku
      @sku = Ec::Sku.find(params[:id])
    end

    def load_category_options
      @category_options = Ec::SkuCategory.active.order(:position, :code)
    end

    def sku_params
      params.require(:ec_sku).permit(
        :sku_code,
        :product_name,
        :product_name_ru,
        :sku_category_id,
        :color,
        :spec,
        :size,
        :weight_kg,
        :volume_l,
        :model,
        :quality_grade,
        :features,
        :owner_name,
        :is_active,
        :memo
      )
    end
  end
end
