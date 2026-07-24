module Reports
  class OzonAdsController < ApplicationController
    before_action -> { require_permission!(:view_reports) }
    before_action :load_context

    helper_method :ozon_ads_comparison_note, :ozon_ads_comparison_label,
      :ozon_ads_comparison_class, :ozon_ads_metric_content

    SUMMARY_METRICS = %i[spend ad_revenue orders_count drr impressions clicks].freeze

    def overview
      @rows = analytics.overview_rows
      @summary = analytics.summary(@rows)
      previous_rows = previous_analytics.overview_rows
      build_comparison(previous_rows, key_builder: ->(row) { [row[:unit_type], row[:placement]] },
        metrics: %i[spend ad_revenue orders_count drr impressions clicks ctr cart_additions])
    end

    def cpc
      @query = params[:q].to_s.strip
      @states = cpc_states
      @rows = analytics.cpc_rows(query: @query, states: @states)
      @summary = analytics.summary(@rows)
      previous_rows = previous_analytics.cpc_rows(query: @query, states: @states)
      build_comparison(previous_rows, key_builder: ->(row) { row[:unit].external_id },
        metrics: %i[spend ad_revenue orders_count impressions clicks cart_additions ctr avg_cpc])
    end

    def cpc_detail
      @unit = RawOzon::AdUnit.where(account_id: @account.id, unit_type: "cpc_campaign").find_by!(external_id: params[:id])
      @query = params[:q].to_s.strip
      @rows = analytics.cpc_detail(@unit, query: @query)
      @summary = analytics.summary(@rows)
      previous_rows = previous_analytics.cpc_detail(@unit, query: @query)
      build_comparison(previous_rows, key_builder: ->(row) { row[:product].ozon_sku_id },
        metrics: %i[spend ad_revenue orders_count impressions clicks cart_additions ctr avg_cpc])
    end

    def cpo_selected
      @query = params[:q].to_s.strip
      @unit, @rows = analytics.cpo_selected_rows(query: @query)
      @summary = analytics.summary(@rows)
      _previous_unit, previous_rows = previous_analytics.cpo_selected_rows(query: @query)
      build_comparison(previous_rows, key_builder: ->(row) { row[:product].ozon_sku_id },
        metrics: %i[spend ad_revenue orders_count drr])
    end

    private

    def load_context
      @stores = Ec::Store.where(platform: "ozon", is_active: true).where.not(ozon_raw_account_id: nil).order(:store_name)
      @store = @stores.find_by(id: params[:store_id]) || @stores.find_by(store_name: "NEVASTAL") || @stores.first
      raise ActiveRecord::RecordNotFound, "No Ozon store configured" unless @store
      @account = @store.raw_ozon_account
      default_from, default_to = default_period
      @to_date = report_date(params[:to_date]) || default_to
      @from_date = report_date(params[:from_date]) || default_from
      @from_date, @to_date = @to_date, @from_date if @from_date > @to_date
      period_days = (@to_date - @from_date).to_i + 1
      @previous_to_date = @from_date - 1.day
      @previous_from_date = @previous_to_date - (period_days - 1).days
    end

    def default_period(today = user_today)
      this_monday = today.beginning_of_week(:monday)
      [this_monday - 1.week, this_monday - 1.day]
    end

    def analytics
      @analytics ||= RawOzon::Ads::AnalyticsQuery.new(
        account: @account, store: @store, from_date: @from_date, to_date: @to_date
      )
    end

    def previous_analytics
      @previous_analytics ||= RawOzon::Ads::AnalyticsQuery.new(
        account: @account, store: @store, from_date: @previous_from_date, to_date: @previous_to_date
      )
    end

    def build_comparison(previous_rows, key_builder:, metrics:)
      builder = RawOzon::Ads::ComparisonBuilder.new
      @summary_comparison = builder.summary(@summary, previous_analytics.summary(previous_rows), metrics: SUMMARY_METRICS)
      @row_comparisons = builder.rows(@rows, previous_rows, key_builder: key_builder, metrics: metrics)
    end

    def report_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def cpc_states
      return %w[CAMPAIGN_STATE_RUNNING CAMPAIGN_STATE_INACTIVE] unless params.key?(:statuses)

      Array(params[:statuses]).filter_map { |state| state.presence_in(RawOzon::AdUnit::STATES) }.uniq
    end

    def ozon_ads_comparison_note
      t("reports.ozon_ads.comparison.note", from: @previous_from_date, to: @previous_to_date)
    end

    def ozon_ads_comparison_label(comparison, include_vs: false)
      return t("reports.ozon_ads.comparison.unavailable") if comparison.blank? || comparison[:delta_pct].nil?

      arrow = { "up" => "↗", "down" => "↘" }.fetch(comparison[:trend], "→")
      suffix = include_vs ? " #{t('reports.ozon_ads.comparison.versus_previous')}" : ""
      "#{arrow} #{format('%.2f', comparison[:delta_pct])}%#{suffix}"
    end

    def ozon_ads_comparison_class(comparison)
      case comparison&.dig(:semantic)
      when "positive" then "is-positive"
      when "negative" then "is-negative"
      when "neutral" then "is-neutral"
      else "is-none"
      end
    end

    def ozon_ads_metric_content(value, comparison)
      helpers.safe_join([
        helpers.content_tag(:span, value),
        helpers.content_tag(:div, ozon_ads_comparison_label(comparison),
          class: "weekly-profit-table-comparison #{ozon_ads_comparison_class(comparison)}")
      ])
    end
  end
end
