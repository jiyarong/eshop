module Ec
  class OperatorSkuMetricsQuery
    PROFIT_KEYS = %i[revenue after_tax margin_pct ads].freeze

    def initialize(skus:, date_to:, time_zone:)
      @skus = skus.to_a
      @sku_codes = @skus.map(&:sku_code)
      @date_to = date_to.to_date
      @time_zone = time_zone
    end

    def call
      return {} if @sku_codes.empty?

      performance = performance_metrics
      inventory = inventory_metrics
      health_results = Ec::RestockingDiagnosis.includes(:events).latest_for_sku_ids(@skus.map(&:id))

      @skus.index_with do |sku|
        code = sku.sku_code
        performance.fetch(sku).merge(
          inventory: inventory.fetch(code, empty_inventory),
          event_count: health_results[sku.id]&.events&.size.to_i
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
      turnover = Ec::InventoryTurnoverMetricsQuery.new(
        sku_codes: @sku_codes,
        date_to: @date_to,
        time_zone: @time_zone
      ).call
      platform_reserved = Ec::SkuInventoryLevel
        .latest
        .where(sku_code: @sku_codes, fulfillment_type: %w[fbo fbw inbound])
        .group(:sku_code)
        .sum(:quantity)
        .transform_keys(&:to_s)

      @sku_codes.index_with do |sku_code|
        metrics = turnover.fetch(sku_code, {})
        {
          available_stock: metrics.fetch(:book_stock, 0).to_i - platform_reserved.fetch(sku_code, 0).to_i,
          incoming_quantity: metrics.fetch(:procurement_stock, 0).to_i,
          turnover_days: metrics[:turnover_days]
        }
      end
    end

    def profit_metrics
      last_week_start = @date_to.beginning_of_week(:monday) - 1.week
      periods = {
        days_7: last_week_start..last_week_start.end_of_week(:monday),
        days_30: (last_week_start - 3.weeks)..last_week_start.end_of_week(:monday)
      }

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
