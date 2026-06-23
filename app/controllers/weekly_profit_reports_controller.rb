class WeeklyProfitReportsController < ApplicationController
  before_action -> { require_permission!(:view_reports) }, except: [:accounts]

  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  WB_COLUMNS = %w[
    nm_id vendor_code region sales_qty return_qty net_qty settlement delivery storage ad goods_cost pre_tax tax after_tax
  ].freeze

  OZON_COLUMNS = %w[
    ozon_sku_id sku_code sales_revenue commission delivery_charge total_ad_cost order_count net_sales_count blr_count
    export_count goods_cost pre_tax_profit after_tax_profit after_tax_margin_pct
  ].freeze

  SUMMARY_LABELS = {
    "total_sales_qty" => "销售件数",
    "total_return_qty" => "退货件数",
    "total_net" => "账面小计",
    "total_goods_cost" => "货物成本",
    "total_pre_tax" => "税前利润",
    "total_tax" => "税额",
    "total_after_tax" => "税后净利",
    "unallocated_rows" => "未分摊行数",
    "sku_count" => "SKU 数",
    "total_sales_revenue" => "销售收入",
    "total_orders" => "订单数",
    "total_returns" => "退货数",
    "total_ad" => "广告费",
    "total_after_tax_profit" => "税后净利",
    "unallocated_total" => "未分摊合计"
  }.freeze

  WB_SUMMARY_KEYS = %w[
    total_sales_qty total_return_qty total_net total_goods_cost total_pre_tax total_tax total_after_tax unallocated_rows
  ].freeze

  OZON_SUMMARY_KEYS = %w[
    sku_count total_sales_revenue total_orders total_returns total_ad total_goods_cost total_after_tax_profit unallocated_total
  ].freeze

  DEFAULT_COLUMNS = {
    "wb" => WB_COLUMNS,
    "ozon" => OZON_COLUMNS
  }.freeze

  SUMMARY_KEYS = {
    "wb" => WB_SUMMARY_KEYS,
    "ozon" => OZON_SUMMARY_KEYS
  }.freeze

  def accounts
    render json: {
      success: true,
      data: {
        wb: wb_accounts.map { |account| account_payload("wb", account) },
        ozon: ozon_accounts.map { |account| account_payload("ozon", account) }
      },
      message: "ok"
    }
  end

  def show
    return render_index if html_index_request?

    parsed = parse_request_params
    return unless parsed

    platform = parsed[:platform]
    account_id = parsed[:account_id]
    from_date = parsed[:from_date]
    to_date = parsed[:to_date]

    unless %w[wb ozon].include?(platform)
      return render_error("unsupported platform: #{platform}", :bad_request)
    end

    account = find_account!(platform, account_id)
    rate = Ec::WeeklyRate.find_by(week_start: from_date.beginning_of_week)
    unless rate
      return render_error("当前周期没有汇率：#{from_date.beginning_of_week}", :unprocessable_entity)
    end

    service = build_service(platform, account_id, from_date, to_date, rate).call

    @report = report_payload(platform, account, from_date, to_date, rate, service)
    respond_to do |format|
      format.html { render partial: "weekly_profit_reports/results", status: :ok }
      format.json { render json: { success: true, data: @report, message: "ok" } }
    end
  rescue ActiveRecord::RecordNotFound
    render_error("店铺不存在或未启用", :not_found)
  rescue => e
    Rails.logger.error("[WeeklyProfitReports] #{e.class}: #{e.message}")
    render_error("internal server error", :internal_server_error)
  end

  helper_method :weekly_profit_column_keys,
                :weekly_profit_summary_keys,
                :weekly_profit_summary_label,
                :weekly_profit_unallocated_rows,
                :weekly_profit_value

  private

  def render_index
    @accounts = { wb: wb_accounts, ozon: ozon_accounts }
    @platform = params[:platform].presence_in(%w[wb ozon]) || "wb"
    @from_date, @to_date = default_period
    render :show
  end

  def html_index_request?
    request.format.html? && !params.key?(:platform)
  end

  def parse_request_params
    {
      platform: params.require(:platform).to_s,
      account_id: Integer(params.require(:account_id)),
      from_date: parse_date(params.require(:from_date)),
      to_date: parse_date(params.require(:to_date))
    }
  rescue ActionController::ParameterMissing, ArgumentError => e
    render_bad_request(e)
    nil
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    raise ArgumentError, "invalid date: #{value}"
  end

  def wb_accounts
    RawWb::SellerAccount.where(is_active: true).order(:id)
  end

  def ozon_accounts
    RawOzon::SellerAccount.where(is_active: true).order(:id)
  end

  def find_account!(platform, account_id)
    case platform
    when "wb"
      RawWb::SellerAccount.where(is_active: true).find(account_id)
    when "ozon"
      RawOzon::SellerAccount.where(is_active: true).find(account_id)
    end
  end

  def account_payload(platform, account)
    {
      id: account.id,
      name: platform == "wb" ? account.name : account.company_name
    }
  end

  def report_payload(platform, account, from_date, to_date, rate, service)
    {
      platform: platform,
      account: account_payload(platform, account),
      period: { from_date: from_date.to_s, to_date: to_date.to_s },
      rates: rate_payload(platform, rate),
      summary: service.summary,
      rows: service.results,
      unallocated: service.unallocated
    }
  end

  def rate_payload(platform, rate)
    payload = { rate_cny_rub: rate.rate_cny_rub }
    payload[:rate_byn_rub] = rate.rate_byn_rub if platform == "wb"
    payload
  end

  def build_service(platform, account_id, from_date, to_date, rate)
    case platform
    when "wb"
      Ec::WbProfitAttribution.new(
        account_id: account_id,
        from_date: from_date,
        to_date: to_date,
        rate_cny_rub: rate.rate_cny_rub,
        rate_byn_rub: rate.rate_byn_rub
      )
    when "ozon"
      Ec::OzonProfitAttribution.new(
        account_id: account_id,
        from_date: from_date,
        to_date: to_date,
        rate_cny_rub: rate.rate_cny_rub,
        sync_missing_ad_costs: false
      )
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

  def weekly_profit_column_keys(report)
    DEFAULT_COLUMNS.fetch(report[:platform])
  end

  def weekly_profit_summary_keys(report)
    SUMMARY_KEYS.fetch(report[:platform])
  end

  def weekly_profit_summary_label(key)
    SUMMARY_LABELS.fetch(key.to_s, key.to_s)
  end

  def weekly_profit_unallocated_rows(report)
    unallocated = report[:unallocated] || {}
    if report[:platform] == "ozon"
      Array(unallocated[:rows] || unallocated["rows"])
    else
      unallocated.map { |name, amount| { "name" => name, "amount" => amount } }
    end
  end

  def weekly_profit_value(row, key)
    value = row[key] || row[key.to_sym]
    return "-" if value.nil? || value == ""
    return format("%.2f", value) if value.is_a?(Float) || value.is_a?(BigDecimal)

    value
  end
end
