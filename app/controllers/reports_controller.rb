class ReportsController < ApplicationController
  helper_method :report_value, :sku_sales_series_name, :sku_detail_tab_path, :platform_label_for_sales
  before_action -> { require_permission!(:view_reports) }
  before_action -> { require_any_permission!(:manage_finance, :manage_skus) }, only: [:new_sku_predicted_cost, :create_sku_predicted_cost]

  SKU_DETAIL_TABS = %w[basic inventory costs stores trend].freeze

  def inventory
    @sku_query = params[:sku].to_s.strip
    @inventory_rows = build_inventory_rows
  end

  def inventory_detail
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    @inventory_detail = Ec::InventoryPageDetailQuery.new(
      @sku,
      detail_tab: params[:detail_tab],
      book_batch_page: params[:book_batch_page],
      date_to: user_today,
      time_zone: user_time_zone
    ).call

    if turbo_frame_request?
      if request.headers["Turbo-Frame"] == "inventory_drawer_content"
        render partial: "reports/inventory_drawer_content_frame", locals: { inventory_detail: @inventory_detail, sku: @sku }
      else
        render :inventory_detail
      end
    else
      render :inventory_detail
    end
  end

  def refresh_inventory_cache
    sku_code = params[:sku_code].to_s.upcase
    Rails.cache.delete(inventory_row_cache_key(sku_code))

    redirect_params = params.permit(:sku, :locale).to_h.compact_blank
    redirect_to redirect_params.present? ? "/reports/inventory?#{redirect_params.to_query}" : "/reports/inventory"
  end

  def skus
    @skus = Ec::Sku.order(:sku_code)
  end

  def sku_detail
    load_sku_detail
  end

  def new_sku_predicted_cost
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    @predicted_cost = @sku.predicted_costs.new(cost_currency: "CNY", effective_from: user_today)
    render :new_sku_predicted_cost_modal
  end

  def create_sku_predicted_cost
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    predicted_cost = @sku.predicted_costs.new(sku_predicted_cost_params)

    if predicted_cost.save
      redirect_to report_sku_path(@sku.sku_code, tab: "costs")
    else
      @predicted_cost = predicted_cost
      render :new_sku_predicted_cost_modal, status: :unprocessable_entity
    end
  end

  def costs
    @sku_costs = Ec::SkuCost.includes(:sku).order(:sku_code)
    @wb_costs = Ec::SkuPlatformCost.includes(:sku, :cost).where(platform: "wb").order(:sku_code, :delivery_mode, :company_type)
    @ozon_costs = Ec::SkuPlatformCost.includes(:sku, :cost).where(platform: "ozon").order(:sku_code, :delivery_mode, :company_type)
  end

  def sku_sales
    @period = params[:period].presence_in(%w[day week month]) || "day"
    @grain = params[:grain].presence_in(%w[store platform sku]) || "store"
    @from_date = parse_report_date(params[:from_date]) || (user_today - 30.days)
    @to_date = parse_report_date(params[:to_date]) || user_today
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

  def load_sku_detail(active_tab: nil)
    @sku = Ec::Sku.includes(:master_sku, :sku_category, :cost, :platform_costs, :store_assignments, :inventory_levels, :sku_products, :predicted_costs).find_by!(sku_code: params[:sku_code].to_s.upcase)
    @active_tab = active_tab || params[:tab].presence_in(SKU_DETAIL_TABS) || "basic"
    @stores = Ec::Store.order(:platform, :store_name)
    @sku_cost = @sku.cost
    @wb_costs = @sku.platform_costs.select { |cost| cost.platform == "wb" }.sort_by { |cost| [cost.delivery_mode.to_s, cost.company_type.to_s] }
    @ozon_costs = @sku.platform_costs.select { |cost| cost.platform == "ozon" }.sort_by { |cost| [cost.delivery_mode.to_s, cost.company_type.to_s] }
    @store_assignments = @sku.store_assignments.sort_by { |assignment| [assignment.platform.to_s, assignment.store_key.to_s] }
    @sku_products = @sku.sku_products.includes(:store).sort_by { |product| [product.platform.to_s, product.store.store_name.to_s, product.product_id.to_s] }
    @predicted_costs = @sku.predicted_costs.sort_by { |cost| [cost.effective_from || Date.new(1900, 1, 1), cost.id || 0] }.reverse
    @predicted_cost ||= @sku.predicted_costs.new(cost_currency: "CNY", effective_from: user_today)

    @overview_from_date = user_today - 30.days
    @overview_to_date = user_today
    @overview_rows = sku_detail_sales_rows(
      sku_products: @sku_products,
      from_date: @overview_from_date,
      to_date: @overview_to_date,
      period: "day",
      grain: "store"
    )
    @overview_summary = build_sku_sales_summary(@overview_rows)
    @overview_store_count = @overview_rows.map { |row| [row[:platform], row[:store_name]] }.uniq.count
    load_sku_inventory_overview if @active_tab == "inventory"

    @from_date = parse_report_date(params[:from_date]) || default_sku_detail_from_date
    @to_date = parse_report_date(params[:to_date]) || user_today
    @period = params[:period].presence_in(%w[day week month]) || "day"
    @grain = params[:grain].presence_in(%w[store platform sku]) || "store"
    @selected_platform = params[:platform].presence_in(Ec::Order::PLATFORMS.values)
    @selected_store_id = params[:store_id].presence

    @sku_sales_rows = sku_detail_sales_rows(
      sku_products: @sku_products,
      from_date: @from_date,
      to_date: @to_date,
      period: sku_detail_sales_period,
      grain: @grain,
      platform: @selected_platform,
      store_id: @selected_store_id
    )
    @sku_sales_summary = build_sku_sales_summary(@sku_sales_rows)
    @sku_sales_chart_series = build_sku_sales_chart_series(@sku_sales_rows)
    @sku_sales_chart_option = build_sku_sales_chart_option(@sku_sales_chart_series)
  end

  def sku_predicted_cost_params
    params.require(:ec_sku_predicted_cost).permit(:cost_money, :cost_currency, :effective_from, :effective_to, :note)
  end

  def build_inventory_rows
    current_page = inventory_page_param
    scope = inventory_skus_scope.order(:sku_code)
    skus = scope.page(current_page).per(10)
    if skus.total_pages.positive? && current_page > skus.total_pages
      skus = scope.page(skus.total_pages).per(10)
    end
    metrics_by_sku = Ec::InventoryVelocityMetricsQuery.new(
      sku_codes: skus.map(&:sku_code),
      date_to: user_today,
      time_zone: user_time_zone
    ).call

    rows = skus.map do |sku|
      fetch_inventory_row(sku, metrics: metrics_by_sku[sku.sku_code] || {})
    end

    Kaminari.paginate_array(
      rows,
      total_count: skus.total_count,
      limit: skus.limit_value,
      offset: skus.offset_value
    )
  end

  def inventory_page_param
    requested_page = params[:jump_page].presence || params[:page].presence
    current_page = params[:current_page].presence || params[:page].presence

    page = requested_page.to_i if requested_page.to_s.match?(/\A\d+\z/)
    page ||= current_page.to_i if current_page.to_s.match?(/\A\d+\z/)
    page = 1 if page.to_i <= 0
    page
  end

  def inventory_skus_scope
    scope = Ec::Sku.all
    return scope if @sku_query.blank?

    scope.where("LOWER(sku_code) LIKE ?", inventory_sku_filter_pattern)
  end

  def inventory_sku_filter_pattern
    "%#{ActiveRecord::Base.sanitize_sql_like(@sku_query.downcase)}%"
  end

  def order_item_sku_product_join_sql
    <<~SQL.squish
      INNER JOIN ec_sku_products
        ON ec_sku_products.store_id = ec_order_items.store_id
       AND ec_sku_products.platform = ec_order_items.platform
       AND (
         (ec_order_items.platform = 'ozon' AND ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id)
         OR
         (ec_order_items.platform = 'wb' AND ec_sku_products.product_id = ec_order_items.platform_sku_id)
       )
    SQL
  end

  def fetch_inventory_row(sku, metrics: {})
    row = Rails.cache.fetch(inventory_row_cache_key(sku.sku_code), expires_in: 30.minutes) do
      Ec::InventoryPageRowQuery.new(sku, metrics: metrics).call
    end

    daily_sales_velocity = metrics[:daily_sales_velocity]
    book_stock = row[:book_stock].to_d
    procurement_stock = row[:incoming_quantity].to_d
    turnover_days = daily_sales_velocity.to_d.positive? ? (book_stock / daily_sales_velocity.to_d) : nil
    turnover_days_with_procurement = daily_sales_velocity.to_d.positive? ? ((book_stock + procurement_stock) / daily_sales_velocity.to_d) : nil

    row.merge(
      daily_sales_velocity: metrics[:daily_sales_velocity],
      turnover_days: turnover_days,
      turnover_days_with_procurement: turnover_days_with_procurement,
      cache_updated_at: Time.current
    )
  end

  def inventory_row_cache_key(sku_code)
    "reports/inventory/rows/#{sku_code}"
  end

  def load_sku_inventory_overview
    @inventory_overview = @sku.inventory_overview
    @inventory_summary = @inventory_overview[:summary]
    @inventory_store_rows = @inventory_overview[:store_rows]
    @latest_inventory_levels = @inventory_overview[:latest_levels]
  end

  def report_value(value)
    return "-" if value.nil? || value == ""
    return format("%.2f", value) if value.is_a?(Float) || value.is_a?(BigDecimal)

    value
  end

  def parse_report_date(value)
    return if value.blank?

    Date.iso8601(value.to_s)
  rescue Date::Error, ArgumentError
    nil
  end

  def default_sku_detail_from_date
    @active_tab == "trend" ? 90.days.ago.to_date : 30.days.ago.to_date
  end

  def sku_detail_sales_period
    @active_tab == "stores" ? "range" : @period
  end

  def sku_detail_tab_path(tab)
    report_sku_path(@sku.sku_code, request.query_parameters.merge(tab: tab).except(:sku_code))
  end

  def build_sku_sales_rows
    rows = sku_sales_relation.map do |row|
      sku_sales_row_hash(row)
    end

    rows.sort_by { |row| [row[:period_start], row[:sku_code].to_s, row[:platform].to_s, row[:store_name].to_s] }
  end

  def sku_detail_sales_rows(sku_products:, from_date:, to_date:, period:, grain:, platform: nil, store_id: nil)
    rows = sku_sales_relation_for(
      sku_product_ids: sku_products.map(&:id),
      from_date: from_date,
      to_date: to_date,
      period: period,
      grain: grain,
      platform: platform,
      store_id: store_id
    ).map do |row|
      sku_sales_row_hash(row)
    end

    rows.sort_by { |row| [row[:period_start], row[:sku_code].to_s, row[:platform].to_s, row[:store_name].to_s] }
  end

  def sku_sales_row_hash(row)
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
      fulfillment_types: row.fulfillment_types.to_s,
      last_ordered_at: row.respond_to?(:last_ordered_at) ? row.last_ordered_at : nil
    }
  end

  def sku_sales_relation_for(sku_codes: nil, sku_product_ids: nil, from_date:, to_date:, period:, grain:, platform: nil, store_id: nil)
    scope = Ec::OrderItem
      .joins(:order, :store)
      .left_joins(:fulfillment)
      .joins(order_item_sku_product_join_sql)
      .joins("LEFT JOIN ec_skus ON ec_skus.sku_code = ec_sku_products.sku_code")
      .where(ec_orders: { ordered_at: user_date_range(from_date, to_date) })
    if !sku_product_ids.nil?
      scope = scope.where(ec_sku_products: { id: sku_product_ids })
    elsif sku_codes.present?
      scope = scope.where(ec_sku_products: { sku_code: sku_codes })
    end
    scope = scope.where(ec_order_items: { platform: platform }) if platform.present?
    scope = scope.where(ec_order_items: { store_id: store_id }) if store_id.present?

    ordered_at_in_user_zone_sql = "(ec_orders.ordered_at AT TIME ZONE 'UTC') AT TIME ZONE #{user_time_zone_sql}"
    period_sql = period == "range" ? "'#{from_date}'::date" : "DATE_TRUNC('#{period}', #{ordered_at_in_user_zone_sql})"
    sku_sql = "ec_sku_products.sku_code"
    platform_sql = grain == "sku" ? "NULL" : "ec_order_items.platform"
    store_sql = grain == "store" ? "ec_stores.store_name" : "NULL"
    group_columns = ["period_start", sku_sql]
    group_columns << "ec_order_items.platform" unless grain == "sku"
    group_columns << "ec_stores.store_name" if grain == "store"
    order_columns = ["period_start ASC", "sku_code ASC"]
    order_columns << "platform ASC" unless grain == "sku"
    order_columns << "store_name ASC" if grain == "store"
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
        "STRING_AGG(DISTINCT ec_order_fulfillments.fulfillment_type, ' / ') AS fulfillment_types",
        "MAX(ec_orders.ordered_at) AS last_ordered_at"
      )
      .group(*group_columns)
      .order(Arel.sql(order_columns.join(", ")))
  end

  def sku_sales_relation
    sku_sales_relation_for(
      sku_product_ids: sku_product_ids_for(@selected_sku_codes),
      from_date: @from_date,
      to_date: @to_date,
      period: @period,
      grain: @grain,
      platform: @selected_platform,
      store_id: @selected_store_id
    )
  end

  def sku_product_ids_for(sku_codes)
    return nil if sku_codes.blank?

    Ec::SkuProduct.where(sku_code: sku_codes).pluck(:id)
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
    t("common.platforms.#{platform}", default: platform.to_s)
  end

  def build_sku_sales_chart_option(series)
    periods = @sku_sales_rows.map { |row| row[:period_start].to_s }.uniq.sort
    net_sales_label = t("reports.sku_detail.metrics.net_sales")
    revenue_label = t("reports.sku_detail.metrics.revenue")
    {
      color: %w[#176b87 #b42318 #167044 #7c3aed #a15c07 #0f766e],
      tooltip: { trigger: "axis" },
      legend: {
        type: "scroll",
        top: 0,
        data: series.flat_map { |item| ["#{sku_sales_series_name(item)} #{net_sales_label}", "#{sku_sales_series_name(item)} #{revenue_label}"] }
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
        { type: "value", name: net_sales_label, minInterval: 1 },
        { type: "value", name: revenue_label }
      ],
      series: series.flat_map do |item|
        values_by_period = item[:rows].index_by { |row| row[:period_start].to_s }
        name = sku_sales_series_name(item)
        [
          {
            name: "#{name} #{net_sales_label}",
            type: "line",
            smooth: true,
            symbolSize: 7,
            yAxisIndex: 0,
            data: periods.map { |period| values_by_period[period]&.fetch(:net_quantity, 0) || 0 }
          },
          {
            name: "#{name} #{revenue_label}",
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
