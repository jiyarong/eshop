module Erp
  class SkusController < BaseController
    before_action :set_sku, only: [:show, :edit, :update, :destroy]
    before_action -> { require_permission!(:manage_skus) }, only: [:new, :create, :edit, :update, :destroy]

    def index
      @category_options = master_sku_category_options
      @q = params[:q].to_s.strip
      @status = params[:status].presence_in(%w[active inactive all]) || "all"
      @category_ids = selected_category_ids

      scope = Ec::MasterSku.includes({ ec_category: :parent }, skus: [:sku_category, :batches]).order(:master_sku_code)
      scope = scope.where(is_active: true) if @status == "active"
      scope = scope.where(is_active: false) if @status == "inactive"
      scope = scope.where(ec_category_id: @category_ids) if @category_ids.any?
      if @q.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.left_joins(:skus).where(
          "ec_master_skus.master_sku_code ILIKE :keyword OR ec_master_skus.product_name ILIKE :keyword OR ec_master_skus.product_name_ru ILIKE :keyword OR ec_skus.sku_code ILIKE :keyword OR ec_skus.product_name ILIKE :keyword OR ec_skus.product_name_ru ILIKE :keyword OR ec_skus.owner_name ILIKE :keyword",
          keyword: keyword
        ).distinct
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
      redirect_to report_sku_path(@sku.sku_code)
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
      render_modal_or_page(:edit, :edit_modal)
    end

    def create
      @sku = Ec::Sku.new(sku_params)
      if @sku.save
        redirect_to erp_skus_path
      else
        load_category_options
        load_master_sku_options
        render_modal_or_page(:new, :new_modal, status: :unprocessable_entity)
      end
    end

    def update
      if @sku.update(sku_params)
        redirect_to erp_skus_path
      else
        load_category_options
        load_master_sku_options
        render_modal_or_page(:edit, :edit_modal, status: :unprocessable_entity)
      end
    end

    def destroy
      @sku.destroy!
      redirect_to erp_skus_path
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
      return [] if @category_ids.any?

      scope = Ec::Sku.includes(:sku_category, :batches).where(master_sku_id: nil).order(:sku_code)
      scope = scope.where(is_active: true) if @status == "active"
      scope = scope.where(is_active: false) if @status == "inactive"
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
      skus.sort_by(&:sku_code)
    end

    def selected_category_ids
      Array(params[:category_ids].presence || params[:category_id])
        .reject(&:blank?)
        .filter_map { |value| Integer(value, exception: false) }
        .uniq
    end

    def master_sku_category_options
      category_ids = Ec::MasterSku.where.not(ec_category_id: nil).distinct.select(:ec_category_id)

      Ec::Category.where(id: category_ids).includes(:parent).to_a
        .map { |category| [master_sku_category_label(category), category.id] }
        .sort_by { |label, id| [label.downcase, id] }
    end

    def master_sku_category_label(category)
      [category.parent&.localized_name, category.localized_name].compact.join(" / ")
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
