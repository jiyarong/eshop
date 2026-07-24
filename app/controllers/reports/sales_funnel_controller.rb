module Reports
  class SalesFunnelController < ApplicationController
    include SpuSkuFilterable

    before_action -> { require_permission!(:view_reports) }

    helper_method :sales_funnel_columns,
                  :sales_funnel_summary_cards,
                  :sales_funnel_value,
                  :sales_funnel_comparison_note,
                  :sales_funnel_row_comparison,
                  :sales_funnel_comparison_label,
                  :sales_funnel_comparison_class

    def show
      return render_index if request.format.html? && request.headers["Turbo-Frame"].blank?

      @report = runner.call
      respond_to do |format|
        format.html { render partial: "reports/sales_funnel/results" }
        format.json { render json: { success: true, data: @report, message: "ok" } }
      end
    rescue ActiveRecord::RecordNotFound
      render_error(t("sales_funnel_reports.errors.store_not_found"), :not_found)
    rescue ActionController::ParameterMissing, ArgumentError => e
      render_error(error_message(e), :unprocessable_entity)
    end

    private

    def render_index
      @store_options = SalesFunnelReports::ReportQueryRunner.store_options
      @selected_store_ref = params[:store_ref].presence || @store_options.first&.dig(:ref)
      @from_date, @to_date = default_period
      @from_date = params[:from_date].presence || @from_date
      @to_date = params[:to_date].presence || @to_date
      load_spu_sku_filter(selected_sku_codes: runner.selected_direct_sku_codes)

      if params[:from_date].blank? || params[:to_date].blank? || (params[:store_ref].blank? && @selected_store_ref.present?)
        redirect_to reports_sales_funnel_path(
          from_date: @from_date,
          to_date: @to_date,
          store_ref: @selected_store_ref,
          master_sku_ids: @spu_sku_selected_master_sku_ids.presence,
          sku_codes: @spu_sku_selected_sku_codes.presence
        ) and return
      end

      @report = runner.call if @selected_store_ref.present?
      render :show
    rescue ActiveRecord::RecordNotFound
      render_error(t("sales_funnel_reports.errors.store_not_found"), :not_found)
    rescue ActionController::ParameterMissing, ArgumentError => e
      render_error(error_message(e), :unprocessable_entity)
    end

    def runner
      @runner ||= SalesFunnelReports::ReportQueryRunner.new(params: params, today: user_today)
    end

    def default_period
      monday = user_today.beginning_of_week(:monday)
      [(monday - 7.days).iso8601, (monday - 1.day).iso8601]
    end

    def error_message(error)
      key = error.is_a?(ActionController::ParameterMissing) ? "missing_parameter" : error.message
      I18n.t("sales_funnel_reports.errors.#{key}", default: error.message)
    end

    def render_error(message, status)
      respond_to do |format|
        format.html { render partial: "reports/sales_funnel/error", locals: { message: message }, status: status }
        format.json { render json: { success: false, message: message }, status: status }
      end
    end

    def sales_funnel_columns(report)
      report.dig(:meta, :columns).map do |key|
        [key, t("sales_funnel_reports.columns.#{report.dig(:meta, :platform)}.#{key}")]
      end
    end

    def sales_funnel_summary_cards(report)
      report[:summary].map do |key, value|
        {
          label: t("sales_funnel_reports.summary.#{key}"),
          value: sales_funnel_value({ key => value }, key),
          comparison: report.dig(:comparison, :summary, key)
        }
      end
    end

    def sales_funnel_value(row, key)
      value = row[key]
      return "-" if value.nil?
      return helpers.number_to_percentage(value, precision: 2) if key.to_s.match?(/(percent|conversion|rate|conv_to_cart|cart_to_order|buyout_percent)\z/)
      return helpers.number_to_currency(value, unit: "", precision: 2) if key.to_s.match?(/(sum|amount|revenue)\z/)
      return helpers.number_with_delimiter(value.to_i) if value.is_a?(Numeric)

      value
    end

    def sales_funnel_comparison_note(report)
      period = report.dig(:comparison, :period)
      t("sales_funnel_reports.comparison.note", from: period[:from_date], to: period[:to_date])
    end

    def sales_funnel_row_comparison(report, row, key)
      report.dig(:comparison, :rows, row[:sku_code].to_s, key)
    end

    def sales_funnel_comparison_label(comparison, include_vs: false)
      return t("sales_funnel_reports.comparison.unavailable") if comparison.blank? || comparison[:trend] == "none" || comparison[:delta_pct].nil?

      arrow = { "up" => "↗", "down" => "↘" }.fetch(comparison[:trend], "→")
      suffix = include_vs ? " #{t('sales_funnel_reports.comparison.versus_previous')}" : ""
      "#{arrow} #{format('%.2f', comparison[:delta_pct])}%#{suffix}"
    end

    def sales_funnel_comparison_class(comparison)
      case comparison&.dig(:semantic)
      when "positive" then "is-positive"
      when "negative" then "is-negative"
      when "neutral" then "is-neutral"
      else "is-none"
      end
    end
  end
end
