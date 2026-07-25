module Reports
  class WbAdsController < ApplicationController
    before_action -> { require_permission!(:view_reports) }
    before_action :load_context

    STATUSES = [-1, 4, 7, 8, 9, 11].freeze

    helper_method :wb_ads_status_class, :wb_ads_status_label, :wb_ads_bid_label,
      :wb_ads_placement_label, :wb_ads_metric, :wb_ads_comparison_note,
      :wb_ads_comparison_label, :wb_ads_comparison_class, :wb_ads_metric_content

    SUMMARY_METRICS = %i[revenue spend drr roas ctr].freeze
    ROW_METRICS = %i[spend views ctr orders drr clicks add_to_cart revenue cpc cpo cr cpm canceled avg_position].freeze

    def index
      if @view == "products"
        @rows = analytics.product_rows(query: @query)
      else
        @rows = analytics.campaign_rows(query: @query, statuses: @statuses)
      end
      @summary = analytics.summary(@rows)
      previous_rows = if @view == "products"
        previous_analytics.product_rows(query: @query)
      else
        previous_analytics.campaign_rows(query: @query, statuses: @statuses)
      end
      build_comparison(previous_rows, key_builder: index_row_key)

      respond_to do |format|
        format.html
        format.json do
          render json: {
            store: { id: @store.id, name: @store.store_name },
            period: { from_date: @from_date, to_date: @to_date },
            view: @view,
            summary: @summary,
            rows: @rows,
          }
        end
      end
    end

    def campaign
      @campaign = RawWb::AdvCampaign.where(store_id: @store.id).find_by!(advert_id: params[:id])
      @budget = @campaign.budget_snapshots.order(observed_at: :desc).first
      @summary = analytics.campaign_summary(@campaign)
      @rows = analytics.campaign_product_rows(@campaign)
      previous_rows = previous_analytics.campaign_product_rows(@campaign)
      build_comparison(previous_rows, key_builder: ->(row) { row[:campaign_product].nm_id })

      respond_to do |format|
        format.html { render partial: "reports/wb_ads/campaign_drawer" if turbo_frame_request? }
        format.json do
          render json: {
            campaign: @campaign,
            budget: @budget,
            period: { from_date: @from_date, to_date: @to_date },
            summary: @summary,
            rows: @rows,
          }
        end
      end
    end

    def product_campaigns
      @nm_id = Integer(params[:nm_id])
      result = analytics.product_campaign_rows(@nm_id)
      @rows = result[:rows]
      @other_row = result[:other_row]
      previous_result = previous_analytics.product_campaign_rows(@nm_id)
      @row_comparisons = comparison_builder.rows(
        @rows, previous_result[:rows], key_builder: ->(row) { row[:campaign].advert_id }, metrics: ROW_METRICS
      )
      @other_comparison = comparison_builder.summary(@other_row || {}, previous_result[:other_row] || {}, metrics: ROW_METRICS)

      respond_to do |format|
        format.html { render partial: "reports/wb_ads/product_campaigns" }
        format.json { render json: result.merge(nm_id: @nm_id) }
      end
    end

    private

    def load_context
      @stores = Ec::Store.active.where(platform: "wb").where.not(wb_api_token: [nil, ""]).order(:store_name)
      @store = @stores.find_by(id: params[:store_id]) || @stores.first
      raise ActiveRecord::RecordNotFound, t("reports.wb_ads.errors.no_store") unless @store

      default_from, default_to = default_period
      @from_date = report_date(params[:from_date]) || default_from
      @to_date = report_date(params[:to_date]) || default_to
      @from_date, @to_date = @to_date, @from_date if @from_date > @to_date
      period_days = (@to_date - @from_date).to_i + 1
      @previous_to_date = @from_date - 1.day
      @previous_from_date = @previous_to_date - (period_days - 1).days
      @query = params[:q].to_s.strip
      @view = params[:view].presence_in(%w[campaigns products]) || "campaigns"
      @statuses = selected_statuses
      @status_options = STATUSES.map { |status| [t("reports.wb_ads.statuses.#{status}"), status.to_s] }
    end

    def analytics
      @analytics ||= RawWb::Adv::AnalyticsQuery.new(store: @store, from_date: @from_date, to_date: @to_date)
    end

    def previous_analytics
      @previous_analytics ||= RawWb::Adv::AnalyticsQuery.new(
        store: @store, from_date: @previous_from_date, to_date: @previous_to_date
      )
    end

    def comparison_builder
      @comparison_builder ||= RawWb::Adv::ComparisonBuilder.new
    end

    def build_comparison(previous_rows, key_builder:)
      @summary_comparison = comparison_builder.summary(
        @summary, previous_analytics.summary(previous_rows), metrics: SUMMARY_METRICS
      )
      @row_comparisons = comparison_builder.rows(
        @rows, previous_rows, key_builder:, metrics: ROW_METRICS
      )
    end

    def index_row_key
      if @view == "products"
        ->(row) { row[:nm_id] }
      else
        ->(row) { row[:campaign].advert_id }
      end
    end

    def default_period
      monday = user_today.beginning_of_week(:monday)
      [monday - 1.week, monday - 1.day]
    end

    def report_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def selected_statuses
      return [9, 11] unless params.key?(:statuses)

      Array(params[:statuses]).filter_map do |status|
        value = Integer(status, exception: false)
        value if STATUSES.include?(value)
      end.uniq
    end

    def wb_ads_status_class(status)
      status == 9 ? "is-active" : "is-muted"
    end

    def wb_ads_status_label(status)
      t("reports.wb_ads.statuses.#{status}", default: status.to_s)
    end

    def wb_ads_bid_label(campaign)
      [
        t("reports.wb_ads.payment_types.#{campaign.payment_type}", default: campaign.payment_type),
        t("reports.wb_ads.bid_types.#{campaign.bid_type}", default: campaign.bid_type)
      ].compact_blank.join(" · ").presence || t("common.empty_value")
    end

    def wb_ads_placement_label(campaign)
      enabled = campaign.placements.select { |_, value| ActiveModel::Type::Boolean.new.cast(value) }.keys
      enabled.map { |placement| t("reports.wb_ads.placements.#{placement}", default: placement) }.join(" / ").presence || t("common.empty_value")
    end

    def wb_ads_metric(value, type: :number, precision: 2)
      return t("common.empty_value") if value.nil?

      case type
      when :currency then helpers.number_to_currency(value, unit: "₽", format: "%n %u", precision:)
      when :percentage then helpers.number_to_percentage(value, precision:)
      when :decimal then helpers.number_with_precision(value, precision:, strip_insignificant_zeros: true)
      else helpers.number_with_delimiter(value.to_i)
      end
    end

    def wb_ads_comparison_note
      t("reports.wb_ads.comparison.note", from: @previous_from_date, to: @previous_to_date)
    end

    def wb_ads_comparison_label(comparison, include_vs: false)
      return t("reports.wb_ads.comparison.unavailable") if comparison.blank? || comparison[:delta_pct].nil?

      arrow = { "up" => "↗", "down" => "↘" }.fetch(comparison[:trend], "→")
      suffix = include_vs ? " #{t('reports.wb_ads.comparison.versus_previous')}" : ""
      "#{arrow} #{format('%.2f', comparison[:delta_pct])}%#{suffix}"
    end

    def wb_ads_comparison_class(comparison)
      case comparison&.dig(:semantic)
      when "positive" then "is-positive"
      when "negative" then "is-negative"
      when "neutral" then "is-neutral"
      else "is-none"
      end
    end

    def wb_ads_metric_content(value, comparison)
      helpers.safe_join([
        helpers.content_tag(:span, value),
        helpers.content_tag(:div, wb_ads_comparison_label(comparison),
          class: "weekly-profit-table-comparison #{wb_ads_comparison_class(comparison)}")
      ])
    end
  end
end
