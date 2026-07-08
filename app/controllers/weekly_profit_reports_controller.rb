class WeeklyProfitReportsController < ApplicationController
  before_action -> { require_permission!(:view_reports) }, except: [:accounts]

  REPORT_TYPES = %w[wr wsu wsu_deep].freeze
  WR_COLUMNS = {
    "wb" => %i[nm_id vendor_code region sales_qty return_qty net_qty settlement delivery storage ad goods_cost pre_tax tax after_tax],
    "ozon" => %i[ozon_sku_id sku_code sales_revenue commission delivery_charge total_ad_cost order_count net_sales_count blr_count export_count goods_cost pre_tax_profit after_tax_profit after_tax_margin_pct]
  }.freeze
  WSU_COLUMNS = %i[sku platform shop net_sales revenue ads goods_cost pre_tax tax after_tax margin_pct previous_net_sales previous_revenue sales_change_pct revenue_change_pct].freeze
  WSU_DEEP_COLUMNS = %i[sku net_sales revenue ads goods_cost pre_tax tax after_tax margin_pct average_profit_per_order ad_ratio_pct cost_return_pct projected_roi_pct annualized_return_pct annualized_net_profit_cny].freeze
  WR_SUMMARY_KEYS = {
    "wb" => %i[total_sales_qty total_return_qty total_net total_goods_cost total_pre_tax total_tax total_after_tax unallocated_rows],
    "ozon" => %i[sku_count total_sales_revenue total_orders total_returns total_ad total_goods_cost total_after_tax_profit unallocated_total]
  }.freeze
  WSU_SUMMARY_KEYS = %i[total_sales_revenue total_after_tax total_margin_pct unallocated_total after_tax_with_unallocated].freeze
  WSU_DEEP_SUMMARY_KEYS = %i[total_sku_count total_net_sales total_sales_revenue total_after_tax unallocated_total after_tax_with_unallocated].freeze

  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  helper_method :weekly_profit_report_summary_cards,
                :weekly_profit_report_table_columns,
                :weekly_profit_report_unallocated_rows,
                :weekly_profit_report_unallocated_columns,
                :weekly_profit_report_value

  def accounts
    render json: {
      success: true,
      data: store_options,
      message: "ok"
    }
  end

  def show
    return render_index if html_index_request?

    @report = run_report_query(parse_request_params)
    respond_to do |format|
      format.html { render partial: "weekly_profit_reports/results", status: :ok }
      format.json { render json: { success: true, data: @report, message: "ok" } }
    end
  rescue ActionController::ParameterMissing => e
    render_bad_request(e)
  rescue ActiveRecord::RecordNotFound
    render_error(t("weekly_profit_reports.errors.store_not_found"), :not_found)
  rescue ArgumentError => e
    status = case e.message
    when "invalid_week_range", "current_week_unsupported", "missing_weekly_rate"
      :unprocessable_entity
    else
      :bad_request
    end
    render_error(error_message_for(e.message), status)
  rescue => e
    Rails.logger.error("[WeeklyProfitReports] #{e.class}: #{e.message}")
    render_error("internal server error", :internal_server_error)
  end

  private

  def render_index
    @store_options = store_options
    @report_type = params[:report_type].presence_in(REPORT_TYPES) || "wr"
    @selected_store_ref = params[:store_ref].presence || @store_options.first&.dig(:ref)
    @from_date, @to_date = default_period
    render :show
  end

  def html_index_request?
    request.format.html? && !params.key?(:report_type)
  end

  def parse_request_params
    report_type = params.require(:report_type).to_s
    raise ArgumentError, "invalid_report_type" unless REPORT_TYPES.include?(report_type)

    parsed = {
      report_type: report_type,
      from_date: parse_date(params.require(:from_date)),
      to_date: parse_date(params.require(:to_date))
    }
    validate_period!(parsed[:from_date], parsed[:to_date])

    if report_type == "wr"
      parsed[:store_ref] = params.require(:store_ref).to_s
    end

    parsed
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    raise ArgumentError, "invalid_date"
  end

  def validate_period!(from_date, to_date)
    raise ArgumentError, "invalid_week_range" unless from_date.cwday == 1 && to_date.cwday == 7
    raise ArgumentError, "invalid_week_range" unless (((to_date - from_date).to_i + 1) % 7).zero?
    raise ArgumentError, "invalid_week_range" if to_date < from_date

    current_monday = user_today.beginning_of_week(:monday)
    raise ArgumentError, "current_week_unsupported" if to_date >= current_monday
  end

  def run_report_query(parsed)
    case parsed[:report_type]
    when "wr"
      Ec::WeeklyProfitReportQuery.run(
        store_ref: parsed[:store_ref],
        from_date: parsed[:from_date],
        to_date: parsed[:to_date]
      )
    when "wsu"
      Ec::WeeklySummaryQuery.run(
        from_date: parsed[:from_date],
        to_date: parsed[:to_date]
      )
    when "wsu_deep"
      Ec::WeeklySummaryDeepQuery.run(
        from_date: parsed[:from_date],
        to_date: parsed[:to_date]
      )
    else
      raise ArgumentError, "invalid_report_type"
    end
  end

  def store_options
    wb_store_options + ozon_store_options
  end

  def wb_store_options
    RawWb::SellerAccount.where(is_active: true).order(:id).map do |account|
      {
        ref: "wb:#{account.id}",
        platform: "wb",
        name: account.name,
        label: "WB · #{account.name}"
      }
    end
  end

  def ozon_store_options
    RawOzon::SellerAccount.where(is_active: true).order(:id).map do |account|
      {
        ref: "ozon:#{account.id}",
        platform: "ozon",
        name: account.company_name,
        label: "Ozon · #{account.company_name}"
      }
    end
  end

  def render_bad_request(error)
    render_error(error.message, :bad_request)
  end

  def render_error(message, status)
    respond_to do |format|
      format.html { render partial: "weekly_profit_reports/error", locals: { message: message }, status: status }
      format.json { render json: { success: false, message: message }, status: status }
    end
  end

  def default_period(today = user_today)
    this_monday = today.beginning_of_week(:monday)
    [(this_monday - 7.days).to_s, (this_monday - 1.day).to_s]
  end

  def error_message_for(code)
    case code
    when "invalid_report_type"
      t("weekly_profit_reports.errors.invalid_report_type")
    when "invalid_store_ref"
      t("weekly_profit_reports.errors.invalid_store_ref")
    when "invalid_date"
      t("weekly_profit_reports.errors.invalid_date")
    when "invalid_week_range"
      t("weekly_profit_reports.errors.invalid_week_range")
    when "current_week_unsupported"
      t("weekly_profit_reports.errors.current_week_unsupported")
    when "missing_weekly_rate"
      t("weekly_profit_reports.errors.missing_weekly_rate")
    else
      code
    end
  end

  def weekly_profit_report_summary_cards(report)
    keys = case report[:report_type]
    when "wr"
      WR_SUMMARY_KEYS.fetch(report.dig(:meta, :platform))
    when "wsu"
      WSU_SUMMARY_KEYS
    when "wsu_deep"
      WSU_DEEP_SUMMARY_KEYS
    else
      []
    end

    keys.map do |key|
      {
        key: key,
        label: t("weekly_profit_reports.summary.#{report[:report_type]}.#{key}"),
        value: weekly_profit_report_value(report[:summary], key)
      }
    end
  end

  def weekly_profit_report_table_columns(report)
    keys = case report[:report_type]
    when "wr"
      WR_COLUMNS.fetch(report.dig(:meta, :platform))
    when "wsu"
      WSU_COLUMNS
    when "wsu_deep"
      WSU_DEEP_COLUMNS
    else
      []
    end

    keys.map do |key|
      [key, t("weekly_profit_reports.columns.#{report[:report_type]}.#{key}")]
    end
  end

  def weekly_profit_report_unallocated_rows(report)
    return [] unless report[:report_type] == "wr"

    unallocated = report.dig(:extras, :unallocated) || {}
    if report.dig(:meta, :platform) == "ozon"
      Array(unallocated[:rows] || unallocated["rows"])
    else
      unallocated.map { |name, amount| { "name" => name, "amount" => amount } }
    end
  end

  def weekly_profit_report_unallocated_columns(report)
    if report.dig(:meta, :platform) == "ozon"
      %i[type_id type_name posting_number amount].map do |key|
        [key, t("weekly_profit_reports.unallocated.ozon.#{key}")]
      end
    else
      %i[name amount].map do |key|
        [key, t("weekly_profit_reports.unallocated.wb.#{key}")]
      end
    end
  end

  def weekly_profit_report_value(row, key)
    value = row[key] || row[key.to_s]
    return "-" if value.nil? || value == ""

    if key.to_s.end_with?("_pct") || key.to_s.include?("margin")
      return "#{format('%.2f', value)}%" if value.is_a?(Numeric) || value.is_a?(BigDecimal)
    end

    return format("%.2f", value) if value.is_a?(Float) || value.is_a?(BigDecimal)

    value
  end
end
