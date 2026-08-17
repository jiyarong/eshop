module Reports
  class SearchTermsController < ApplicationController
    include SpuSkuFilterable

    before_action -> { require_permission!(:view_reports) }
    before_action :load_context

    helper_method :search_terms_metric, :search_terms_metric_content, :search_terms_comparison_label,
      :search_terms_comparison_class, :search_terms_top_order_options

    def index
      @rows = @valid_period ? report_query.rows : []
      @row_comparisons = @valid_period ? comparison_builder.rows(@rows, previous_report_query.rows) : {}

      respond_to do |format|
        format.html
        format.json { render json: { platform: @platform, store: @store, period: period_json, valid_period: @valid_period, rows: @rows } }
      end
    end

    def terms
      @sku_code = params[:sku_code].to_s.upcase
      @terms = if @valid_period
        comparison_builder.terms(
          report_query.terms_for(@sku_code),
          previous_report_query.terms_for(@sku_code),
          include_lost: @platform != "wb"
        )
      else
        []
      end

      respond_to do |format|
        format.html { render partial: "reports/search_terms/terms" }
        format.json { render json: { sku_code: @sku_code, terms: @terms } }
      end
    end

    private

    def load_context
      @stores = Ec::Store.active.where(platform: SearchTermReports::Query::PLATFORMS).order(:platform, :store_name)
      requested_store = @stores.find_by(id: params[:store_id])
      @platform = requested_store&.platform || params[:platform].presence_in(SearchTermReports::Query::PLATFORMS) || "wb"
      @store = requested_store || @stores.find { |store| store.platform == @platform }
      raise ActiveRecord::RecordNotFound, t("reports.search_terms.errors.no_store") unless @store

      @from_date, @to_date, @valid_period = requested_period
      if @valid_period
        @previous_from_date = @from_date - 1.week
        @previous_to_date = @to_date - 1.week
      end
      @query = params[:q].to_s.strip
      @top_order_by = params[:top_order_by].to_s.presence_in(RawWb::AnalyticsSearchTerm::TOP_ORDER_BY_VALUES) ||
        RawWb::AnalyticsSearchTerm::TOP_ORDER_BY_VALUES.first
      if action_name == "index"
        load_spu_sku_filter
        @selected_sku_codes = apply_spu_sku_filter_to_skus(Ec::Sku.all).pluck(:sku_code) if spu_sku_filter_active?
      end
    end

    def requested_period
      default_from, default_to = default_period
      return [default_from, default_to, true] if params[:from_date].blank? && params[:to_date].blank?

      from = Date.iso8601(params[:from_date].to_s)
      to = Date.iso8601(params[:to_date].to_s)
      valid = from.monday? && to.sunday? && to == from + 6.days
      [from, to, valid]
    rescue Date::Error
      [params[:from_date], params[:to_date], false]
    end

    def default_period
      monday = user_today.beginning_of_week(:monday)
      [monday - 1.week, monday - 1.day]
    end

    def report_query
      @report_query ||= SearchTermReports::Query.new(
        platform: @platform,
        store: @store,
        period_from: @from_date,
        period_to: @to_date,
        sku_codes: @selected_sku_codes,
        query: @query,
        top_order_by: @top_order_by
      )
    end

    def previous_report_query
      @previous_report_query ||= SearchTermReports::Query.new(
        platform: @platform,
        store: @store,
        period_from: @previous_from_date,
        period_to: @previous_to_date,
        sku_codes: @selected_sku_codes,
        query: @query,
        top_order_by: @top_order_by
      )
    end

    def comparison_builder
      @comparison_builder ||= SearchTermReports::ComparisonBuilder.new
    end

    def period_json
      { from_date: @from_date, to_date: @to_date }
    end

    def search_terms_top_order_options
      RawWb::AnalyticsSearchTerm::TOP_ORDER_BY_VALUES.map do |value|
        [t("reports.search_terms.detail.top_order_by.options.#{value}"), value]
      end
    end

    def search_terms_metric(value, type: :number)
      return t("common.empty_value") if value.nil?

      case type
      when :currency then helpers.number_to_currency(value, unit: "₽", format: "%n %u", precision: 2)
      when :percentage then helpers.number_to_percentage(value, precision: 2)
      when :decimal then helpers.number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
      else helpers.number_with_delimiter(value.to_i)
      end
    end

    def search_terms_metric_content(value, comparison, type: :number, comparison_type: :percentage)
      helpers.safe_join([
        helpers.content_tag(:span, search_terms_metric(value, type:)),
        helpers.content_tag(:div, search_terms_comparison_label(comparison, type: comparison_type),
          class: "weekly-profit-table-comparison #{search_terms_comparison_class(comparison)}")
      ])
    end

    def search_terms_comparison_label(comparison, type: :percentage)
      return t("reports.search_terms.comparison.unavailable") if comparison.blank? || comparison[:state] == :unavailable
      return t("reports.search_terms.comparison.new") if comparison[:state] == :new
      return t("reports.search_terms.comparison.lost.#{@platform}") if comparison[:state] == :lost

      value = type == :percentage ? comparison[:delta_pct] : comparison[:delta]
      return t("reports.search_terms.comparison.unavailable") if value.nil?
      return t("reports.search_terms.comparison.unchanged") if value.zero?

      key = value.positive? ? "up" : "down"
      formatted = helpers.number_with_precision(value.abs, precision: 2, strip_insignificant_zeros: true)
      t("reports.search_terms.comparison.#{type}.#{key}", value: formatted)
    end

    def search_terms_comparison_class(comparison)
      case comparison&.dig(:semantic)
      when :positive then "is-positive"
      when :negative then "is-negative"
      when :neutral then "is-neutral"
      else "is-none"
      end
    end
  end
end
