module Ec
  class SkuActualSellingPriceQuery
    DEFAULT_WEEKS = 4
    PLATFORMS = %w[wb ozon].freeze
    MARKETS = %w[ru by].freeze

    def self.run(sku:, platform:, market:, today:, time_zone:, weeks: DEFAULT_WEEKS)
      new(sku:, platform:, market:, today:, time_zone:, weeks:).run
    end

    def initialize(sku:, platform:, market:, today:, time_zone:, weeks: DEFAULT_WEEKS)
      @sku = sku
      @platform = platform.to_s.downcase
      @market = market.to_s.downcase
      @today = today.to_date
      @time_zone = time_zone
      @weeks = Integer(weeks)
      raise ArgumentError, "unsupported_platform" unless PLATFORMS.include?(@platform)
      raise ArgumentError, "unsupported_market" unless MARKETS.include?(@market)
      raise ArgumentError, "weeks_must_be_positive" unless @weeks.positive?
    end

    def run
      period_to = today.beginning_of_week(:monday) - 1.day
      period_from = period_to - (weeks * 7 - 1).days
      rows = order_rows(period_from:, period_to:)
      expected_rows = rows.select { |row| row.fetch(:currency) == source_currency }
      converted_rows = convert_to_rub(expected_rows)
      source_quantity = expected_rows.sum { |row| row.fetch(:quantity) }
      converted_quantity = converted_rows.sum { |row| row.fetch(:quantity) }
      missing_rate_count = expected_rows.size - converted_rows.size

      {
        platform: platform,
        market: market,
        period: {
          from_date: period_from,
          to_date: period_to,
          data_through: expected_rows.filter_map { |row| row.fetch(:ordered_at)&.in_time_zone(time_zone)&.to_date }.max
        },
        price: {
          source_currency: source_currency,
          average_source: weighted_average(expected_rows, :source_price, source_quantity),
          average_rub: missing_rate_count.zero? ? weighted_average(converted_rows, :rub_price, converted_quantity) : nil,
          item_count: expected_rows.size,
          unit_count: source_quantity,
          missing_exchange_rate_item_count: missing_rate_count
        }
      }
    end

    private

    attr_reader :sku, :platform, :market, :today, :time_zone, :weeks

    def source_currency
      platform == "ozon" && market == "by" ? "BYN" : "RUB"
    end

    def order_rows(period_from:, period_to:)
      active_store_ids = Ec::Store.active.where(platform: platform).ids
      return [] if active_store_ids.empty?

      Ec::OrderItem
        .joins(:order)
        .joins(order_item_sku_product_join_sql)
        .where(ec_sku_products: { sku_code: sku.sku_code, is_active: true })
        .where(ec_order_items: { platform: platform, store_id: active_store_ids })
        .where(ec_orders: { ordered_at: user_time_range(period_from, period_to) })
        .where.not(ec_orders: { order_status: "cancelled" })
        .where("ec_order_items.quantity > 0")
        .where("ec_order_items.buyer_paid_unit_price > 0")
        .where.not(ec_order_items: { buyer_currency_code: [nil, ""] })
        .distinct
        .pluck(
          "ec_order_items.id",
          "ec_order_items.buyer_paid_unit_price",
          "ec_order_items.buyer_currency_code",
          "ec_order_items.quantity",
          "ec_orders.ordered_at"
        ).map do |id, price, currency, quantity, ordered_at|
          {
            id: id,
            source_price: price.to_d,
            currency: currency.to_s.upcase,
            quantity: quantity.to_i,
            ordered_at: ordered_at
          }
        end
    end

    def convert_to_rub(rows)
      return rows.map { |row| row.merge(rub_price: row.fetch(:source_price)) } if source_currency == "RUB"

      dates = rows.filter_map { |row| row.fetch(:ordered_at)&.in_time_zone(time_zone)&.to_date }.uniq
      rates = Ec::DailyExchangeRate
        .where(rate_date: dates, base_currency: "CNY", currency_code: [source_currency, "RUB"])
        .index_by { |rate| [rate.rate_date, rate.currency_code] }

      rows.filter_map do |row|
        date = row.fetch(:ordered_at)&.in_time_zone(time_zone)&.to_date
        source_rate = rates[[date, source_currency]]
        rub_rate = rates[[date, "RUB"]]
        next unless source_rate && rub_rate

        row.merge(rub_price: row.fetch(:source_price) * source_rate.rate_to_base / rub_rate.rate_to_base)
      end
    end

    def weighted_average(rows, key, total_quantity)
      return if total_quantity.zero?

      rows.sum { |row| row.fetch(key) * row.fetch(:quantity) }.then { |total| (total / total_quantity).round(2) }
    end

    def user_time_range(from_date, to_date)
      time_zone.local(from_date.year, from_date.month, from_date.day).beginning_of_day..
        time_zone.local(to_date.year, to_date.month, to_date.day).end_of_day
    end

    def order_item_sku_product_join_sql
      <<~SQL.squish
        INNER JOIN ec_sku_products
          ON ec_sku_products.store_id = ec_order_items.store_id
         AND ec_sku_products.platform = ec_order_items.platform
         AND ((ec_order_items.platform = 'ozon' AND ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id)
           OR (ec_order_items.platform = 'wb' AND ec_sku_products.product_id = ec_order_items.platform_sku_id))
      SQL
    end
  end
end
