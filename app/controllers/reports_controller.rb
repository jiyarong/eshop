class ReportsController < ApplicationController
  helper_method :report_value, :sku_sales_series_name
  before_action -> { require_permission!(:view_reports) }

  def inventory
    @snapshots = Ec::InventorySnapshot.includes(:sku).order(:sku_code, :platform, :account_id)
    @totals = Ec::InventoryTotal.includes(:sku).order(:sku_code)
  end

  def skus
    @skus = Ec::Sku.order(:sku_code)
  end

  def costs
    @sku_costs = Ec::SkuCost.includes(:sku).order(:sku_code)
    @wb_costs = Ec::SkuPlatformCost.includes(:sku, :cost).where(platform: "wb").order(:sku_code, :delivery_mode, :company_type)
    @ozon_costs = Ec::SkuPlatformCost.includes(:sku, :cost).where(platform: "ozon").order(:sku_code, :delivery_mode, :company_type)
  end

  def sku_sales
    @period = params[:period].presence_in(%w[day week month]) || "day"
    @grain = params[:grain].presence_in(%w[store platform sku]) || "store"
    @from_date = parse_report_date(params[:from_date]) || 30.days.ago.to_date
    @to_date = parse_report_date(params[:to_date]) || Time.zone.today
    @stores = Ec::Store.order(:platform, :store_name)
    @skus = Ec::Sku.order(:sku_code)
    @selected_sku_codes = selected_sku_codes
    @selected_platform = params[:platform].presence_in(Ec::Order::PLATFORMS.values)
    @selected_store_id = params[:store_id].presence
    @sku_sales_rows = build_sku_sales_rows
    @sku_sales_summary = build_sku_sales_summary(@sku_sales_rows)
    @sku_sales_chart_series = build_sku_sales_chart_series(@sku_sales_rows)
    @sku_sales_chart_option = build_sku_sales_chart_option(@sku_sales_chart_series)
  end

  private

  def report_value(value)
    return "-" if value.nil? || value == ""
    return format("%.2f", value) if value.is_a?(Float) || value.is_a?(BigDecimal)

    value
  end

  def parse_report_date(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def build_sku_sales_rows
    rows = sku_sales_relation.map do |row|
      {
        period_start: row.period_start.to_date,
        sku_code: row.sku_code,
        product_name: row.product_name,
        platform: row.platform,
        store_name: row.store_name,
        sales_quantity: row.sales_quantity.to_i,
        return_quantity: row.return_quantity.to_i,
        net_quantity: row.net_quantity.to_i,
        order_count: row.order_count.to_i,
        gross_revenue: row.gross_revenue.to_d,
        payout: row.payout.to_d,
        commission: row.commission.to_d,
        discount: row.discount.to_d,
        average_unit_price: row.average_unit_price.to_d,
        fulfillment_types: row.fulfillment_types.to_s
      }
    end

    rows.sort_by { |row| [row[:period_start], row[:sku_code].to_s, row[:platform].to_s, row[:store_name].to_s] }
  end

  def sku_sales_relation
    scope = Ec::OrderItem
      .joins(:order, :store)
      .left_joins(:fulfillment)
      .joins("LEFT JOIN ec_skus ON ec_skus.sku_code = ec_order_items.sku_code")
      .where(ec_orders: { ordered_at: @from_date.beginning_of_day..@to_date.end_of_day })
    if @selected_sku_codes.present?
      scope = scope.where("ec_order_items.sku_code IN (:skus) OR ec_order_items.offer_id IN (:skus)", skus: @selected_sku_codes)
    end
    scope = scope.where(ec_order_items: { platform: @selected_platform }) if @selected_platform.present?
    scope = scope.where(ec_order_items: { store_id: @selected_store_id }) if @selected_store_id.present?

    period_sql = "DATE_TRUNC('#{@period}', ec_orders.ordered_at)"
    sku_sql = "COALESCE(ec_order_items.sku_code, ec_order_items.offer_id, ec_order_items.platform_sku_id)"
    platform_sql = @grain == "sku" ? "NULL" : "ec_order_items.platform"
    store_sql = @grain == "store" ? "ec_stores.store_name" : "NULL"
    group_columns = ["period_start", sku_sql]
    group_columns << "ec_order_items.platform" unless @grain == "sku"
    group_columns << "ec_stores.store_name" if @grain == "store"
    order_columns = ["period_start ASC", "sku_code ASC"]
    order_columns << "platform ASC" unless @grain == "sku"
    order_columns << "store_name ASC" if @grain == "store"
    sales_case = "CASE WHEN ec_orders.order_status = 'returned' THEN 0 ELSE ec_order_items.quantity END"
    return_case = "CASE WHEN ec_orders.order_status = 'returned' THEN ec_order_items.quantity ELSE 0 END"

    scope
      .select(
        "#{period_sql} AS period_start",
        "#{sku_sql} AS sku_code",
        "MAX(ec_skus.product_name) AS product_name",
        "#{platform_sql} AS platform",
        "#{store_sql} AS store_name",
        "SUM(#{sales_case}) AS sales_quantity",
        "SUM(#{return_case}) AS return_quantity",
        "SUM(#{sales_case}) - SUM(#{return_case}) AS net_quantity",
        "COUNT(DISTINCT ec_orders.id) AS order_count",
        "SUM(ec_order_items.quantity * COALESCE(ec_order_items.unit_price, 0)) AS gross_revenue",
        "SUM(COALESCE(ec_order_items.payout, 0)) AS payout",
        "SUM(COALESCE(ec_order_items.commission_amount, 0)) AS commission",
        "SUM(COALESCE(ec_order_items.discount_amount, 0)) AS discount",
        "AVG(ec_order_items.unit_price) AS average_unit_price",
        "STRING_AGG(DISTINCT ec_order_fulfillments.fulfillment_type, ' / ') AS fulfillment_types"
      )
      .group(*group_columns)
      .order(Arel.sql(order_columns.join(", ")))
  end

  def build_sku_sales_summary(rows)
    {
      sales_quantity: rows.sum { |row| row[:sales_quantity] },
      return_quantity: rows.sum { |row| row[:return_quantity] },
      net_quantity: rows.sum { |row| row[:net_quantity] },
      order_count: rows.sum { |row| row[:order_count] },
      gross_revenue: rows.sum { |row| row[:gross_revenue] },
      payout: rows.sum { |row| row[:payout] },
      commission: rows.sum { |row| row[:commission] }
    }
  end

  def build_sku_sales_chart_series(rows)
    rows
      .group_by { |row| [row[:sku_code], row[:platform], row[:store_name]] }
      .map do |(sku_code, platform, store_name), grouped_rows|
        {
          sku_code: sku_code,
          platform: platform,
          store_name: store_name,
          rows: grouped_rows.sort_by { |row| row[:period_start] }
        }
      end
      .sort_by { |series| [series[:sku_code].to_s, series[:platform].to_s, series[:store_name].to_s] }
  end

  def sku_sales_series_name(series)
    [series[:sku_code], platform_label_for_sales(series[:platform]), series[:store_name]].compact_blank.join(" / ")
  end

  def platform_label_for_sales(platform)
    {
      "ozon" => "Ozon",
      "wb" => "WB",
      "amazon" => "Amazon"
    }.fetch(platform.to_s, platform.to_s)
  end

  def build_sku_sales_chart_option(series)
    periods = @sku_sales_rows.map { |row| row[:period_start].to_s }.uniq.sort
    {
      color: %w[#176b87 #b42318 #167044 #7c3aed #a15c07 #0f766e],
      tooltip: { trigger: "axis" },
      legend: {
        type: "scroll",
        top: 0,
        data: series.flat_map { |item| ["#{sku_sales_series_name(item)} 净销量", "#{sku_sales_series_name(item)} 销售额"] }
      },
      grid: {
        left: 48,
        right: 24,
        top: 52,
        bottom: 42,
        containLabel: true
      },
      xAxis: {
        type: "category",
        boundaryGap: false,
        data: periods
      },
      yAxis: [
        { type: "value", name: "净销量", minInterval: 1 },
        { type: "value", name: "销售额" }
      ],
      series: series.flat_map do |item|
        values_by_period = item[:rows].index_by { |row| row[:period_start].to_s }
        name = sku_sales_series_name(item)
        [
          {
            name: "#{name} 净销量",
            type: "line",
            smooth: true,
            symbolSize: 7,
            yAxisIndex: 0,
            data: periods.map { |period| values_by_period[period]&.fetch(:net_quantity, 0) || 0 }
          },
          {
            name: "#{name} 销售额",
            type: "line",
            smooth: true,
            symbolSize: 7,
            yAxisIndex: 1,
            data: periods.map { |period| values_by_period[period]&.fetch(:gross_revenue, 0)&.to_f || 0 }
          }
        ]
      end
    }
  end

  def selected_sku_codes
    values = params[:sku_codes].presence || params[:sku_code].presence
    Array(values).map(&:presence).compact
  end
end
