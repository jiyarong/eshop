class ReportsController < ApplicationController
  helper_method :report_value, :sku_sales_series_name, :sku_detail_tab_path, :platform_label_for_sales
  before_action -> { require_permission!(:view_reports) }
  before_action -> { require_any_permission!(:manage_finance, :manage_skus) }, only: [:new_sku_predicted_cost, :create_sku_predicted_cost]

  SKU_DETAIL_TABS = %w[basic inventory costs stores trend].freeze

  def inventory
    @sku_query = params[:sku].to_s.strip
    @inventory_rows = build_inventory_rows
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
    inventory_skus_scope.includes(:batches, :sku_products, inventory_levels: :store).order(:sku_code).map do |sku|
      fetch_inventory_row(sku)
    end
  end

  def inventory_skus_scope
    scope = Ec::Sku.all
    return scope if @sku_query.blank?

    scope.where("LOWER(sku_code) LIKE ?", inventory_sku_filter_pattern)
  end

  def latest_inventory_quantity(levels, platform:, fulfillment_type:)
    levels.sum do |level|
      level.platform == platform && level.fulfillment_type == fulfillment_type ? level.quantity : 0
    end
  end

  def wb_sales_by_fulfillment(sku)
    rows = Hash.new(0)
    condition_sql = inventory_order_item_match_sql(sku, platform: "wb")
    return rows if condition_sql.blank?

    Ec::OrderItem
      .joins(:order)
      .left_joins(:fulfillment)
      .where(condition_sql)
      .where(ec_order_items: { platform: "wb" })
      .where.not(ec_orders: { order_status: %w[cancelled returned] })
      .group("COALESCE(ec_order_fulfillments.fulfillment_type, 'unknown')")
      .sum(:quantity)
      .each do |fulfillment_type, quantity|
        rows[fulfillment_type.to_s] = quantity.to_i
      end

    rows
  end

  def inventory_order_item_match_sql(sku, platform:)
    predicates = ["ec_order_items.sku_code = #{ActiveRecord::Base.connection.quote(sku.sku_code)}"]
    sku.sku_products.select { |product| product.platform == platform }.each do |product|
      ids = [product.product_id, product.platform_sku_id, product.offer_id].compact_blank.uniq
      next if ids.empty?

      quoted_ids = ids.map { |value| ActiveRecord::Base.connection.quote(value.to_s) }.join(", ")
      predicates << ActiveRecord::Base.sanitize_sql_array(
        [
          "(ec_order_items.platform = ? AND ec_order_items.store_id = ? AND (ec_order_items.platform_sku_id IN (#{quoted_ids}) OR ec_order_items.offer_id IN (#{quoted_ids})))",
          product.platform,
          product.store_id
        ]
      )
    end

    predicates.join(" OR ")
  end

  def inventory_sku_filter_pattern
    "%#{ActiveRecord::Base.sanitize_sql_like(@sku_query.downcase)}%"
  end

  def fetch_inventory_row(sku)
    Rails.cache.fetch(inventory_row_cache_key(sku.sku_code), expires_in: 30.minutes) do
      build_inventory_row(sku).merge(cache_updated_at: Time.current)
    end
  end

  def build_inventory_row(sku)
    overview = sku.inventory_overview
    summary = overview[:summary]
    store_rows = overview[:store_rows]
    latest_levels = overview[:latest_levels]
    wb_rows = store_rows.select { |row| row[:platform] == "wb" }
    ozon_rows = store_rows.select { |row| row[:platform] == "ozon" }
    wb_fulfillment_sales = wb_sales_by_fulfillment(sku)
    wb_net = wb_rows.sum { |row| row[:sales_quantity] } - wb_rows.sum { |row| row[:return_quantity] }
    ozon_sales = ozon_rows.sum { |row| row[:sales_quantity] }
    ozon_return = ozon_rows.sum { |row| row[:return_quantity] }
    purchase_quantity = summary[:received_quantity]
    net_sales = wb_net + ozon_sales - ozon_return
    platform_stock = summary[:platform_stock]
    book_stock = purchase_quantity - net_sales

    {
      sku_code: sku.sku_code,
      purchase_quantity: purchase_quantity,
      wb_fbs: wb_fulfillment_sales["fbs"],
      wb_fbw: wb_fulfillment_sales["fbw"],
      wb_return: wb_rows.sum { |row| row[:return_quantity] },
      wb_net: wb_net,
      ozon_sales: ozon_sales,
      ozon_return: ozon_return,
      net_sales: net_sales,
      book_stock: book_stock,
      wb_fbw_available: latest_inventory_quantity(latest_levels, platform: "wb", fulfillment_type: "fbw"),
      wb_fbs_available: latest_inventory_quantity(latest_levels, platform: "wb", fulfillment_type: "fbs"),
      ozon_fbo: latest_inventory_quantity(latest_levels, platform: "ozon", fulfillment_type: "fbo"),
      ozon_fbs: latest_inventory_quantity(latest_levels, platform: "ozon", fulfillment_type: "fbs"),
      platform_stock: platform_stock,
      belarus_available: book_stock - platform_stock
    }
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
      .joins(<<~SQL.squish)
        LEFT JOIN ec_sku_products ON ec_sku_products.store_id = ec_order_items.store_id
          AND ec_sku_products.product_id = CASE
            WHEN ec_order_items.platform = 'ozon' THEN (
              SELECT raw_ozon_products.ozon_product_id::text
              FROM raw_ozon_products
              JOIN ec_stores product_stores ON product_stores.ozon_raw_account_id = raw_ozon_products.account_id
              WHERE product_stores.id = ec_order_items.store_id
                AND (
                  raw_ozon_products.ozon_product_id::text = ec_order_items.platform_sku_id
                  OR raw_ozon_products.raw_json ->> 'sku' = ec_order_items.platform_sku_id
                  OR raw_ozon_products.offer_id = ec_order_items.offer_id
                )
              ORDER BY raw_ozon_products.id
              LIMIT 1
            )
            ELSE COALESCE(ec_order_items.platform_sku_id, ec_order_items.offer_id)
          END
      SQL
      .joins("LEFT JOIN ec_skus ON ec_skus.sku_code = COALESCE(ec_sku_products.sku_code, ec_order_items.sku_code)")
      .where(ec_orders: { ordered_at: user_date_range(from_date, to_date) })
    if !sku_product_ids.nil?
      scope = scope.where(ec_sku_products: { id: sku_product_ids })
    elsif sku_codes.present?
      scope = scope.where("COALESCE(ec_sku_products.sku_code, ec_order_items.sku_code) IN (:skus)", skus: sku_codes)
    end
    scope = scope.where(ec_order_items: { platform: platform }) if platform.present?
    scope = scope.where(ec_order_items: { store_id: store_id }) if store_id.present?

    ordered_at_in_user_zone_sql = "(ec_orders.ordered_at AT TIME ZONE 'UTC') AT TIME ZONE #{user_time_zone_sql}"
    period_sql = period == "range" ? "'#{from_date}'::date" : "DATE_TRUNC('#{period}', #{ordered_at_in_user_zone_sql})"
    sku_sql = "COALESCE(ec_sku_products.sku_code, ec_order_items.sku_code, ec_order_items.offer_id, ec_order_items.platform_sku_id)"
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
