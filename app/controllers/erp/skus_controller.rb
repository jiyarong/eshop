module Erp
  class SkusController < BaseController
    before_action :set_sku, only: [:show, :edit, :update]
    before_action -> { require_permission!(:manage_skus) }, only: [:new, :create, :edit, :update]

    def index
      @categories = Ec::SkuCategory.active.order(:position, :code)
      @q = params[:q].to_s.strip
      @status = params[:status].presence_in(%w[active inactive all]) || "all"
      @category_id = params[:category_id].presence

      scope = Ec::MasterSku.includes(skus: [:sku_category, :batches]).order(:master_sku_code)
      scope = scope.where(is_active: true) if @status == "active"
      scope = scope.where(is_active: false) if @status == "inactive"
      scope = scope.joins(:skus).where(ec_skus: { sku_category_id: @category_id }).distinct if @category_id.present?
      if @q.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.where(
          "ec_master_skus.master_sku_code ILIKE :keyword OR ec_master_skus.product_name ILIKE :keyword OR ec_master_skus.product_name_ru ILIKE :keyword",
          keyword: keyword
        )
      end

      @master_skus = scope.to_a
      @master_sku_entries = @master_skus.map do |master_sku|
        {
          master_sku: master_sku,
          skus: skus_for_display(master_sku.skus)
        }
      end
      @orphan_skus = orphan_sku_scope
      @product_counts = {
        master_total: Ec::MasterSku.count,
        sku_total: Ec::Sku.count,
        batch_total: Ec::SkuBatch.count,
        active_master_total: Ec::MasterSku.active.count
      }
    end

    def show
    end

    def new
      @sku = Ec::Sku.new(is_active: true)
      @sku.master_sku_id = params[:master_sku_id] if params[:master_sku_id].present?
      load_category_options
      load_master_sku_options
      render_modal_or_page(:new, :new_modal)
    end

    def edit
      load_category_options
      load_master_sku_options
    end

    def create
      @sku = Ec::Sku.new(sku_params)
      if @sku.save
        redirect_to erp_sku_path(@sku)
      else
        load_category_options
        load_master_sku_options
        render_modal_or_page(:new, :new_modal, status: :unprocessable_entity)
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

    def load_master_sku_options
      @master_sku_options = Ec::MasterSku.order(:master_sku_code)
    end

    def orphan_sku_scope
      scope = Ec::Sku.includes(:sku_category, :batches).where(master_sku_id: nil).order(:sku_code)
      scope = scope.where(is_active: true) if @status == "active"
      scope = scope.where(is_active: false) if @status == "inactive"
      scope = scope.where(sku_category_id: @category_id) if @category_id.present?
      if @q.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.where(
          "ec_skus.sku_code ILIKE :keyword OR ec_skus.product_name ILIKE :keyword OR ec_skus.product_name_ru ILIKE :keyword OR ec_skus.owner_name ILIKE :keyword",
          keyword: keyword
        )
      end
      scope.to_a
    end

    def skus_for_display(skus)
      visible_skus = skus.sort_by(&:sku_code)
      visible_skus = visible_skus.select { |sku| sku.sku_category_id == @category_id.to_i } if @category_id.present?
      visible_skus
    end

    def sku_params
      params.require(:ec_sku).permit(
        :sku_code,
        :master_sku_id,
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
