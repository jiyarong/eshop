module Ec
  class SkuActualSellingPriceQuery
    DEFAULT_WEEKS = 4
    PLATFORMS = %w[wb ozon].freeze
    MARKETS = %w[ru by].freeze

    FULFILLMENT_MODES = { "fbo" => %w[fbo fbw], "fbs" => %w[fbs] }.freeze

    # delivery_mode (optional) narrows to FBO/FBW or FBS orders.
    def self.run(sku:, platform:, market:, today:, time_zone:, weeks: DEFAULT_WEEKS, delivery_mode: nil)
      new(sku:, platform:, market:, today:, time_zone:, weeks:, delivery_mode:).run
    end

    def initialize(sku:, platform:, market:, today:, time_zone:, weeks: DEFAULT_WEEKS, delivery_mode: nil)
      @sku = sku
      @platform = platform.to_s.downcase
      @market = market.to_s.downcase
      @today = today.to_date
      @time_zone = time_zone
      @weeks = Integer(weeks)
      @delivery_mode = delivery_mode.to_s.downcase.presence
      raise ArgumentError, "unsupported_delivery_mode" if @delivery_mode && !FULFILLMENT_MODES.key?(@delivery_mode)
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
      all_rows = order_rows(period_from:, period_to:)
      wb_markets = platform == "wb" ? Ec::WbLedgerMarket.markets_by_srid(all_rows.map { |row| row[:external_order_id] }) : {}
      rows = rows_in_market(all_rows, wb_markets)
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
        delivery_mode: delivery_mode,
        # WB orders whose market the ledger does not know yet (this week's): counted as Russian.
        unclassified_unit_count: all_rows.reject { |row| wb_markets.key?(row[:external_order_id]) }.sum { |row| row.fetch(:quantity) } * (platform == "wb" ? 1 : 0),
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

    attr_reader :sku, :platform, :market, :today, :time_zone, :weeks, :delivery_mode

    def market_buyer_currency
      platform == "ozon" && market == "by" ? "BYN" : "RUB"
    end

    # Ozon orders are told apart by the currency the buyer paid in, so an Ozon item without buyer
    # data cannot be assigned to one. WB orders have no buyer country: their market is the one of
    # the ledger's sale row for the same srid. An order the ledger has not reached yet (shipped,
    # this week's) has none; it counts as Russian, the usual market, and is reported in
    # `unclassified_unit_count`, while the Belarus price rests on orders the ledger places there.
    def rows_in_market(rows, wb_markets)
      return rows.select { |row| row.fetch(:buyer_currency) == market_buyer_currency } unless platform == "wb"

      rows.select do |row|
        known = wb_markets[row[:external_order_id]]
        market == "ru" ? known.nil? || known == "ru" : known == "by"
      end
    end

    def order_rows(period_from:, period_to:)
      active_store_ids = Ec::Store.active.where(platform: platform).ids
      return [] if active_store_ids.empty?

      Ec::OrderItem
        .joins(:order)
        .joins(order_item_sku_product_join_sql)
        .where(ec_sku_products: { sku_code: sku.sku_code, is_active: true })
        .where(ec_order_items: { platform: platform, store_id: active_store_ids })
        .then { |scope| fulfillment_scope(scope) }
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
          "ec_orders.ordered_at",
          "ec_orders.external_order_id"
        ).map do |id, commission_base_price, commission_base_currency, buyer_paid_price, buyer_currency, quantity, ordered_at, external_order_id|
          {
            id: id,
            external_order_id: external_order_id,
            commission_base_price: commission_base_price&.to_d,
            commission_base_currency: commission_base_currency.to_s.upcase.presence,
            buyer_paid_price: buyer_paid_price&.to_d,
            buyer_currency: buyer_currency.to_s.upcase.presence,
            quantity: quantity.to_i,
            ordered_at: ordered_at
          }
        end
    end

    def fulfillment_scope(scope)
      return scope unless delivery_mode

      scope
        .joins("INNER JOIN ec_order_fulfillments ON ec_order_fulfillments.id = ec_order_items.fulfillment_id")
        .where(ec_order_fulfillments: { fulfillment_type: FULFILLMENT_MODES.fetch(delivery_mode) })
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
