class OperatorSkusController < ApplicationController
  include ResponsibleUserFilterable
  include SpuSkuFilterable
  include SkuMarketingStateFilterable
  include MasterSkuCategoryFilterable
  include AIDiagnosisEventFilterable
  include TableSortable

  PAGE_SIZE = 10
  SORT_METRIC_PATHS = {
    "sales" => %i[sales days_30 value],
    "revenue" => %i[profit days_30 revenue value],
    "profit" => %i[profit days_30 after_tax value],
    "margin" => %i[profit days_30 margin_pct value],
    "ads" => %i[profit days_30 ads value]
  }.freeze

  before_action -> { require_permission!(:view_erp) }

  def index
    @q = params[:q].to_s.strip
    load_master_sku_category_filter
    load_sku_marketing_state_filters
    load_spu_sku_filter
    load_responsible_user_filters
    load_ai_diagnosis_event_filter
    load_table_sort(allowed_keys: SORT_METRIC_PATHS.keys, default_key: "profit")

    scope = Ec::Sku.includes(
      :master_sku,
      :current_marketing_state,
      :developers,
      sku_products: :operators
    ).order(:sku_code)
    scope = apply_master_sku_category_filter_to_skus(scope)
    scope = apply_spu_sku_filter_to_skus(scope)
    scope = apply_responsible_user_filters_to_skus(scope)
    scope = apply_marketing_state_filters(scope)
    scope = apply_ai_diagnosis_event_filter_to_skus(scope)
    if @q.present?
      keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
      scope = scope.left_joins(:master_sku).where(
        "ec_skus.sku_code ILIKE :keyword OR ec_skus.product_name ILIKE :keyword OR ec_master_skus.master_sku_code ILIKE :keyword OR ec_master_skus.product_name ILIKE :keyword",
        keyword: keyword
      ).distinct
    end

    if table_sort_key.present?
      all_skus = scope.to_a
      all_metrics = metrics_for(all_skus)
      sorted_skus = sort_table_records(all_skus) { |sku| all_metrics.fetch(sku).dig(*SORT_METRIC_PATHS.fetch(table_sort_key)) }
      @skus = Kaminari.paginate_array(sorted_skus).page(page_param).per(PAGE_SIZE)
      @skus = Kaminari.paginate_array(sorted_skus).page(@skus.total_pages).per(PAGE_SIZE) if @skus.total_pages.positive? && @skus.current_page > @skus.total_pages
      @metrics_by_sku = @skus.index_with { |sku| all_metrics.fetch(sku) }
    else
      @skus = scope.page(page_param).per(PAGE_SIZE)
      @skus = scope.page(@skus.total_pages).per(PAGE_SIZE) if @skus.total_pages.positive? && @skus.current_page > @skus.total_pages
      @metrics_by_sku = metrics_for(@skus)
    end
    load_latest_red_ai_diagnosis_events_for(@skus)
  end

  private

  def metrics_for(skus)
    Ec::OperatorSkuMetricsQuery.new(
      skus: skus,
      date_to: user_today,
      time_zone: user_time_zone
    ).call
  end

  def page_param
    requested_page = params[:jump_page].presence || params[:page].presence
    current_page = params[:current_page].presence || params[:page].presence
    page = Integer(requested_page, exception: false).to_i
    page = Integer(current_page, exception: false).to_i unless page.positive?
    page.positive? ? page : 1
  end
end
