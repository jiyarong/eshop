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

    # Both prices are independent facts of an order item, with the same meaning on
    # every platform:
    #   commission_base_price  the price the platform charges commission on
    #                          (ec_order_items.unit_price)
    #   buyer_paid_price       what the buyer actually paid
    #                          (ec_order_items.buyer_paid_unit_price)
    # Neither is derived from the other, and neither row set depends on the other.
    def run
      period_to = today.beginning_of_week(:monday) - 1.day
      period_from = period_to - (weeks * 7 - 1).days
      rows = order_rows(period_from:, period_to:).select { |row| in_market?(row) }
      commission_base_price = summarize_price(
        rows,
        amount_key: :commission_base_price,
        currency_key: :commission_base_currency,
        default_currency: "RUB"
      )
      buyer_paid_price = summarize_price(
        rows,
        amount_key: :buyer_paid_price,
        currency_key: :buyer_currency,
        default_currency: market_buyer_currency
      )

      {
        platform: platform,
        market: market,
        period: {
          from_date: period_from,
          to_date: period_to,
          data_through: rows.filter_map { |row| row.fetch(:ordered_at)&.in_time_zone(time_zone)&.to_date }.max
        },
        commission_base_price: commission_base_price,
        buyer_paid_price: buyer_paid_price
      }
    end

    private

    attr_reader :sku, :platform, :market, :today, :time_zone, :weeks

    def market_buyer_currency
      platform == "ozon" && market == "by" ? "BYN" : "RUB"
    end

    # WB has a single market here. Ozon orders are told apart by the currency the
    # buyer paid in, so an Ozon item without buyer data cannot be assigned to one.
    def in_market?(row)
      platform == "wb" || row.fetch(:buyer_currency) == market_buyer_currency
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
        .where("ec_order_items.unit_price > 0 OR ec_order_items.buyer_paid_unit_price > 0")
        .distinct
        .pluck(
          "ec_order_items.id",
          "ec_order_items.unit_price",
          "ec_order_items.currency_code",
          "ec_order_items.buyer_paid_unit_price",
          "ec_order_items.buyer_currency_code",
          "ec_order_items.quantity",
          "ec_orders.ordered_at"
        ).map do |id, commission_base_price, commission_base_currency, buyer_paid_price, buyer_currency, quantity, ordered_at|
          {
            id: id,
            commission_base_price: commission_base_price&.to_d,
            commission_base_currency: commission_base_currency.to_s.upcase.presence,
            buyer_paid_price: buyer_paid_price&.to_d,
            buyer_currency: buyer_currency.to_s.upcase.presence,
            quantity: quantity.to_i,
            ordered_at: ordered_at
          }
        end
    end

    def summarize_price(rows, amount_key:, currency_key:, default_currency:)
      usable_rows = rows.select do |row|
        row[amount_key].present? && row.fetch(amount_key).positive? && row[currency_key].present?
      end
      currencies = usable_rows.map { |row| row.fetch(currency_key) }.uniq
      converted_rows = convert_to_rub(usable_rows, amount_key:, currency_key:)
      source_quantity = usable_rows.sum { |row| row.fetch(:quantity) }
      converted_quantity = converted_rows.sum { |row| row.fetch(:quantity) }
      missing_rate_count = usable_rows.size - converted_rows.size

      {
        source_currency: currencies.one? ? currencies.first : (default_currency if currencies.empty?),
        average_source: currencies.one? ? weighted_average(usable_rows, amount_key, source_quantity) : nil,
        average_rub: missing_rate_count.zero? ? weighted_average(converted_rows, :rub_price, converted_quantity) : nil,
        item_count: usable_rows.size,
        unit_count: source_quantity,
        missing_exchange_rate_item_count: missing_rate_count
      }
    end

    def convert_to_rub(rows, amount_key:, currency_key:)
      dates = rows.filter_map do |row|
        next if row.fetch(currency_key) == "RUB"

        row.fetch(:ordered_at)&.in_time_zone(time_zone)&.to_date
      end.uniq
      currencies = rows.map { |row| row.fetch(currency_key) }.uniq - ["RUB"]
      rates = Ec::DailyExchangeRate
        .where(rate_date: dates, base_currency: "CNY", currency_code: currencies + ["RUB"])
        .index_by { |rate| [rate.rate_date, rate.currency_code] }

      rows.filter_map do |row|
        amount = row.fetch(amount_key)
        currency = row.fetch(currency_key)
        next row.merge(rub_price: amount) if currency == "RUB"

        date = row.fetch(:ordered_at)&.in_time_zone(time_zone)&.to_date
        source_rate = rates[[date, currency]]
        rub_rate = rates[[date, "RUB"]]
        next unless source_rate && rub_rate

        row.merge(rub_price: amount * source_rate.rate_to_base / rub_rate.rate_to_base)
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
