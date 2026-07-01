module Ec
  class InventoryVelocityMetricsQuery
    WINDOW_DAYS = [7, 15, 30].freeze
    WINDOW_WEIGHTS = {
      7 => BigDecimal("0.5"),
      15 => BigDecimal("0.3"),
      30 => BigDecimal("0.2")
    }.freeze

    def initialize(sku_codes:, date_to:, time_zone:)
      @sku_codes = Array(sku_codes).map(&:to_s).map(&:upcase).uniq
      @date_to = date_to
      @time_zone = time_zone
    end

    def call
      return {} if @sku_codes.empty?

      sales_by_window = WINDOW_DAYS.to_h do |window_days|
        [window_days, sales_quantity_by_sku(window_days)]
      end

      @sku_codes.index_with do |sku_code|
        {
          daily_sales_velocity: weighted_daily_sales_velocity(sku_code, sales_by_window),
          turnover_days: nil
        }
      end
    end

    private

    def weighted_daily_sales_velocity(sku_code, sales_by_window)
      WINDOW_DAYS.sum(BigDecimal("0")) do |window_days|
        quantity = sales_by_window.fetch(window_days, {}).fetch(sku_code, 0).to_d
        (quantity / window_days) * WINDOW_WEIGHTS.fetch(window_days)
      end
    end

    def sales_quantity_by_sku(window_days)
      from_date = @date_to - (window_days - 1).days

      Ec::OrderItem
        .joins(:order)
        .joins(order_item_sku_product_join_sql)
        .where(ec_sku_products: { sku_code: @sku_codes })
        .where.not(ec_orders: { order_status: "cancelled" })
        .where(ec_orders: { ordered_at: user_date_range(from_date, @date_to) })
        .group("ec_sku_products.sku_code")
        .sum(:quantity)
        .transform_keys(&:to_s)
        .transform_values(&:to_i)
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

    def user_date_range(from_date, to_date)
      time_for_user_date(from_date).beginning_of_day..time_for_user_date(to_date).end_of_day
    end

    def time_for_user_date(date)
      @time_zone.local(date.year, date.month, date.day)
    end
  end
end
