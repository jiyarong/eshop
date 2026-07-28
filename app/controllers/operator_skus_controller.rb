class OperatorSkusController < ApplicationController
  include ResponsibleUserFilterable
  include SpuSkuFilterable
  include SkuMarketingStateFilterable
  include MasterSkuCategoryFilterable

  PAGE_SIZE = 10

  before_action -> { require_permission!(:view_erp) }

  def index
    @q = params[:q].to_s.strip
    load_master_sku_category_filter
    load_sku_marketing_state_filters
    load_spu_sku_filter
    load_responsible_user_filters

    scope = Ec::Sku.active.includes(
      :master_sku,
      :current_marketing_state,
      :developers,
      sku_products: :operators
    ).order(:sku_code)
    scope = apply_master_sku_category_filter_to_skus(scope)
    scope = apply_spu_sku_filter_to_skus(scope)
    scope = apply_responsible_user_filters_to_skus(scope)
    scope = apply_marketing_state_filters(scope)
    if @q.present?
      keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
      scope = scope.left_joins(:master_sku).where(
        "ec_skus.sku_code ILIKE :keyword OR ec_skus.product_name ILIKE :keyword OR ec_master_skus.master_sku_code ILIKE :keyword OR ec_master_skus.product_name ILIKE :keyword",
        keyword: keyword
      ).distinct
    end

    @skus = scope.page(page_param).per(PAGE_SIZE)
    @skus = scope.page(@skus.total_pages).per(PAGE_SIZE) if @skus.total_pages.positive? && @skus.current_page > @skus.total_pages
    @metrics_by_sku = Ec::OperatorSkuMetricsQuery.new(
      skus: @skus,
      date_to: user_today,
      time_zone: user_time_zone
    ).call
  end

  private

  def page_param
    requested_page = params[:jump_page].presence || params[:page].presence
    current_page = params[:current_page].presence || params[:page].presence
    page = Integer(requested_page, exception: false).to_i
    page = Integer(current_page, exception: false).to_i unless page.positive?
    page.positive? ? page : 1
  end
end
