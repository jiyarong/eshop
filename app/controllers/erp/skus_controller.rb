module Erp
  class SkusController < BaseController
    include ResponsibleUserFilterable
    include SpuSkuFilterable

    SKU_PAGE_SIZE = 10

    before_action :set_sku, only: [:show, :edit, :update, :destroy]
    before_action -> { require_permission!(:manage_skus) }, only: [:new, :create, :edit, :update, :destroy]

    def index
      @q = params[:q].to_s.strip
      @status = params[:status].presence_in(%w[active inactive all]) || "all"
      @master_sku_id = Integer(params[:master_sku_id], exception: false)
      @grades = selected_marketing_grades
      @stages = selected_marketing_stages
      load_spu_sku_filter
      load_responsible_user_filters

      scope = Ec::Sku.includes(
        :master_sku,
        :sku_category,
        :batches,
        :current_marketing_state,
        :developers,
        sku_products: :operators
      ).order(:sku_code)
      scope = scope.where(is_active: true) if @status == "active"
      scope = scope.where(is_active: false) if @status == "inactive"
      scope = apply_spu_sku_filter_to_skus(scope)
      scope = apply_responsible_user_filters_to_skus(scope)
      scope = apply_marketing_state_filters(scope)
      if @q.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.left_joins(:master_sku).where(
          "ec_skus.sku_code ILIKE :keyword OR ec_skus.product_name ILIKE :keyword OR ec_skus.product_name_ru ILIKE :keyword OR ec_skus.owner_name ILIKE :keyword OR ec_master_skus.master_sku_code ILIKE :keyword OR ec_master_skus.product_name ILIKE :keyword OR ec_master_skus.product_name_ru ILIKE :keyword",
          keyword: keyword
        ).distinct
      end

      @skus = paginated_skus(scope)
      @sku_counts = {
        master_total: Ec::MasterSku.count,
        sku_total: Ec::Sku.count,
        batch_total: Ec::SkuBatch.count,
        active_sku_total: Ec::Sku.active.count
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
        redirect_to safe_return_to(erp_skus_path(current_locale_params))
      else
        load_category_options
        load_master_sku_options
        render_modal_or_page(:new, :new_modal, status: :unprocessable_entity)
      end
    end

    def update
      if @sku.update(sku_params)
        redirect_to safe_return_to(erp_skus_path(current_locale_params))
      else
        load_category_options
        load_master_sku_options
        render_modal_or_page(:edit, :edit_modal, status: :unprocessable_entity)
      end
    end

    def destroy
      @sku.destroy!
      redirect_to safe_return_to(erp_skus_path(current_locale_params))
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

    def paginated_skus(scope)
      current_page = sku_page_param
      skus = scope.page(current_page).per(SKU_PAGE_SIZE)
      if skus.total_pages.positive? && current_page > skus.total_pages
        skus = scope.page(skus.total_pages).per(SKU_PAGE_SIZE)
      end
      skus
    end

    def sku_page_param
      requested_page = params[:jump_page].presence || params[:page].presence
      current_page = params[:current_page].presence || params[:page].presence

      page = requested_page.to_i if requested_page.to_s.match?(/\A\d+\z/)
      page ||= current_page.to_i if current_page.to_s.match?(/\A\d+\z/)
      page = 1 if page.to_i <= 0
      page
    end

    def selected_marketing_grades
      Array(params[:grades].presence || params[:grade])
        .reject(&:blank?)
        .map { |value| value.to_s.upcase }
        .select { |value| Ec::SkuMarketingState::GRADES.include?(value) }
        .uniq
    end

    def selected_marketing_stages
      Array(params[:stages].presence || params[:stage])
        .reject(&:blank?)
        .map { |value| value.to_s.downcase }
        .select { |value| Ec::SkuMarketingState::STAGES.include?(value) }
        .uniq
    end

    def apply_marketing_state_filters(scope)
      return scope if @grades.blank? && @stages.blank?

      scope = scope.joins(:current_marketing_state)
      scope = scope.where(ec_sku_marketing_states: { grade: @grades }) if @grades.present?
      scope = scope.where(ec_sku_marketing_states: { stage: @stages }) if @stages.present?
      scope
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
