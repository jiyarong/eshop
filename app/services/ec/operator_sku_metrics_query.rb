module Ec
  class OperatorSkuMetricsQuery
    PROFIT_KEYS = %i[net_sales revenue after_tax margin_pct ads ad_ratio_pct annualized_return_pct annualized_net_profit_cny].freeze

    def initialize(skus:, date_to:, time_zone:, include_days_30: true)
      @skus = skus.to_a
      @sku_codes = @skus.map(&:sku_code)
      @date_to = date_to.to_date
      @time_zone = time_zone
      @include_days_30 = include_days_30
    end

    def call
      return {} if @sku_codes.empty?

      performance = performance_metrics
      inventory = inventory_metrics
      distribution = Ec::OperatorSkuInventoryDistributionQuery.new(sku_codes: @sku_codes).call
      last_week_start = @date_to.beginning_of_week(:monday) - 1.week
      sales_funnel = Ec::OperatorSkuSalesFunnelMetricsQuery.new(
        skus: @skus, from_date: last_week_start,
        to_date: last_week_start.end_of_week(:monday), time_zone: @time_zone
      ).call

      @skus.index_with do |sku|
        code = sku.sku_code
        performance.fetch(sku).merge(
            inventory: inventory.fetch(code, empty_inventory)
            .merge(distribution: distribution.fetch(code, {})),
          sales_funnel: sales_funnel.fetch(sku, {})
        )
      end
    end

    def performance_metrics
      return {} if @sku_codes.empty?

      sales = sales_quantities
      profit = profit_metrics

      @skus.index_with do |sku|
        code = sku.sku_code
        {
          sales: sales.fetch(code, empty_sales),
          profit: profit.fetch(code, empty_profit)
        }
      end
    end

    private

    def sales_quantities
      from_60_days = user_day_start(@date_to - 59.days)
      from_30_days = user_day_start(@date_to - 29.days)
      from_14_days = user_day_start(@date_to - 13.days)
      from_7_days = user_day_start(@date_to - 6.days)
      to_time = user_day_end(@date_to)

      rows = Ec::OrderItem
        .joins(:order)
        .joins(order_item_sku_product_join_sql)
        .where(ec_sku_products: { sku_code: @sku_codes })
        .where.not(ec_orders: { order_status: "cancelled" })
        .where(ec_orders: { ordered_at: from_60_days..to_time })
        .group("ec_sku_products.sku_code")
        .pluck(
          Arel.sql("ec_sku_products.sku_code"),
          Arel.sql("SUM(CASE WHEN ec_orders.ordered_at >= #{quoted_time(from_7_days)} AND ec_orders.order_status <> 'returned' THEN ec_order_items.quantity ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN ec_orders.ordered_at >= #{quoted_time(from_14_days)} AND ec_orders.ordered_at < #{quoted_time(from_7_days)} AND ec_orders.order_status <> 'returned' THEN ec_order_items.quantity ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN ec_orders.ordered_at >= #{quoted_time(from_30_days)} AND ec_orders.order_status <> 'returned' THEN ec_order_items.quantity ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN ec_orders.ordered_at < #{quoted_time(from_30_days)} AND ec_orders.order_status <> 'returned' THEN ec_order_items.quantity ELSE 0 END)")
        )

      rows.each_with_object({}) do |(sku_code, days_7, previous_7, days_30, previous_30), result|
        result[sku_code.to_s] = {
          days_7: sales_period_metric(days_7, previous_7),
          days_30: sales_period_metric(days_30, previous_30)
        }
      end
    end

    def sales_period_metric(current, previous)
      current = current.to_i
      previous = previous.to_i
      delta_pct = previous.zero? ? nil : (((current - previous).to_d / previous) * 100).round(2)
      semantic = if delta_pct.nil? || delta_pct.zero?
        "neutral"
      elsif delta_pct.positive?
        "positive"
      else
        "negative"
      end

      {
        value: current,
        comparison: { current: current, previous: previous, delta_pct: delta_pct, semantic: semantic }
      }
    end

    def inventory_metrics
      overview = Ec::SkuInventoryOverviewBatchQuery.new(skus: @skus).call
      velocity = Ec::InventoryVelocityMetricsQuery.new(
        sku_codes: @sku_codes,
        date_to: @date_to,
        time_zone: @time_zone
      ).call
      strict_result = ErpAI::DynamicDailySalesForecast.new(
        skus: @skus,
        date_to: @date_to - 1.day
      ).call
      strict_forecasts = @skus.one? ? { @skus.first => strict_result } : strict_result
      @sku_codes.index_with do |sku_code|
        summary = overview.fetch(sku_code, {})
        velocity_metrics = velocity.fetch(sku_code, {})
        sku = @skus.find { |record| record.sku_code == sku_code }
        strict = sku ? strict_forecasts.fetch(sku, {}) : {}
        strict_daily_sales = strict[:forecast_daily_sales]
        book_stock = summary.fetch(:book_stock, 0).to_d
        platform_stock = summary.fetch(:platform_stock, 0).to_d
        simple_velocity = velocity_metrics[:daily_sales_velocity].to_d
        {
          book_stock: book_stock.to_i,
          platform_stock: platform_stock.to_i,
          available_stock: platform_stock.to_i,
          incoming_quantity: summary.fetch(:incoming_quantity, 0).to_i,
          daily_sales_velocity: velocity_metrics[:daily_sales_velocity],
          forecast_explanation: velocity_metrics[:forecast_explanation],
          turnover_days: simple_velocity.positive? ? (book_stock / simple_velocity).round(2) : nil,
          strict_forecast: strict.merge(
            cover_days: strict_daily_sales.to_d.positive? ? (book_stock / strict_daily_sales.to_d).round(2) : nil
          )
        }
      end
    end

    def profit_metrics
      last_week_start = @date_to.beginning_of_week(:monday) - 1.week
      periods = {
        days_7: last_week_start..last_week_start.end_of_week(:monday)
      }
      periods[:days_30] = (last_week_start - 3.weeks)..last_week_start.end_of_week(:monday) if @include_days_30

      period_metrics = periods.transform_values do |period|
        profit_metrics_for_period(period.begin, period.end)
      end

      @sku_codes.index_with do |sku_code|
        periods.keys.index_with do |period_key|
          period_metrics.fetch(period_key).fetch(sku_code, empty_profit_period)
        end
      end
    end

    def profit_metrics_for_period(from_date, to_date)
      report = Ec::WeeklySummaryDeepQuery.run(from_date:, to_date:, sku_codes: @sku_codes)
      comparisons = report.dig(:comparison, :rows) || {}

      report.fetch(:rows).each_with_object({}) do |row, result|
        sku_code = row.fetch(:sku).to_s
        result[sku_code] = PROFIT_KEYS.index_with do |key|
          {
            value: row[key],
            comparison: comparisons.dig(sku_code, key)
          }
        end
      end
    rescue RuntimeError => error
      raise unless error.message.start_with?("找不到 ")

      {}
    end

    def empty_inventory
      { available_stock: 0, incoming_quantity: 0, turnover_days: nil }
    end

    def empty_sales
      %i[days_7 days_30].index_with { sales_period_metric(0, 0) }
    end

    def empty_profit
      %i[days_7 days_30].index_with { empty_profit_period }
    end

    def empty_profit_period
      PROFIT_KEYS.index_with { |key| { value: nil, comparison: nil } }
    end

    def user_day_start(date)
      @time_zone.local(date.year, date.month, date.day).beginning_of_day
    end

    def user_day_end(date)
      @time_zone.local(date.year, date.month, date.day).end_of_day
    end

    def quoted_time(value)
      ActiveRecord::Base.connection.quote(value)
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
  end
end
