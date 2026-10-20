module Ec
  # The return rate the calculators' return amortization needs: return legs billed per outbound
  # leg billed, on both platforms. A returned unit costs its outbound leg plus its return leg, and
  # so does every cancelled or refused parcel that never became a sale, so the calculator adds
  # (outbound + return) x r / (1 - r) per net sale; only a rate counted in logistics legs
  # reproduces what the profit attribution charges. The buyer-side rate from the orders table
  # (WB only: Ozon orders have no "returned" status) is kept in `buyer_return_rate` for reference.
  class SkuActualReturnRateQuery
    DEFAULT_WEEKS = 4
    PLATFORMS = %w[wb ozon].freeze

    def self.run(sku:, platform:, today:, time_zone:, weeks: DEFAULT_WEEKS, delivery_mode: nil, market: nil)
      new(sku:, platform:, today:, time_zone:, weeks:, delivery_mode:, market:).run
    end

    def initialize(sku:, platform:, today:, time_zone:, weeks: DEFAULT_WEEKS, delivery_mode: nil, market: nil)
      @sku = sku
      @platform = platform.to_s.downcase
      @today = today.to_date
      @time_zone = time_zone
      @weeks = Integer(weeks)
      @delivery_mode = delivery_mode.to_s.downcase.presence
      @market = market.to_s.downcase.presence
      raise ArgumentError, "unsupported_platform" unless PLATFORMS.include?(@platform)
      raise ArgumentError, "weeks_must_be_positive" unless @weeks.positive?
    end

    def run
      return ozon_payload if platform == "ozon"

      wb_payload
    end

    private

    attr_reader :sku, :platform, :today, :time_zone, :weeks, :delivery_mode, :market

    def ozon_payload
      payload = Ec::SkuActualLogisticsQuery.run(sku:, today:, delivery_mode:, weeks:)

      payload.slice(:platform, :delivery_mode, :period, :store_count, :listing_count, :return_rate)
    end

    # Return legs ("От клиента при возврате / при отмене") per outbound leg ("К клиенту при
    # продаже / при отмене"), counted per parcel in the 4-week finance details, for the
    # scenario's delivery mode when given.
    def wb_payload
      logistics = Ec::SkuActualLogisticsQuery.run(sku:, today:, platform: "wb", delivery_mode:, market:, weeks:)
      outbound_count = logistics.dig(:outbound, :sample_count).to_i
      return_count = logistics.dig(:return, :sample_count).to_i

      logistics.slice(:platform, :delivery_mode, :market, :period, :store_count, :listing_count).merge(
        return_rate: {
          order_count: outbound_count,
          return_count: return_count,
          rate: outbound_count.positive? ? (return_count.to_d / outbound_count).round(10) : nil
        },
        # The buyer-side rate comes from the orders table, which cannot be told apart by market.
        buyer_return_rate: market ? nil : wb_buyer_return_rate
      )
    end

    def wb_buyer_return_rate
      period_to = today.beginning_of_week(:monday) - 1.day
      period_from = period_to - (weeks * 7 - 1).days
      rows = wb_order_rows(period_from:, period_to:)
      order_count = rows.sum { |row| row.fetch(:quantity) }
      return_count = rows.sum { |row| row.fetch(:status) == "returned" ? row.fetch(:quantity) : 0 }

      {
        order_count: order_count,
        return_count: return_count,
        rate: order_count.positive? ? (return_count.to_d / order_count).round(10) : nil
      }
    end

    def wb_order_rows(period_from:, period_to:)
      return [] if wb_bindings.empty?

      allowed_bindings = wb_bindings.to_set
      Ec::OrderItem
        .joins(:order)
        .where(ec_order_items: { platform: "wb", store_id: allowed_bindings.map(&:first).uniq })
        .where(ec_orders: {
          order_status: %w[delivered returned],
          ordered_at: user_time_range(period_from, period_to)
        })
        .where.not(ec_order_items: { platform_sku_id: [nil, ""] })
        .where("ec_order_items.quantity > 0")
        .distinct
        .pluck(
          "ec_order_items.id",
          "ec_order_items.store_id",
          "ec_order_items.platform_sku_id",
          "ec_order_items.quantity",
          "ec_orders.order_status",
          "ec_orders.ordered_at"
        ).filter_map do |_id, store_id, platform_sku_id, quantity, status, ordered_at|
          next unless allowed_bindings.include?([store_id, platform_sku_id.to_s])

          { quantity: quantity.to_i, status: status, ordered_at: ordered_at }
        end
    end

    def wb_bindings
      @wb_bindings ||= sku.sku_products
        .active
        .joins(:store)
        .merge(Ec::Store.active.where(platform: "wb"))
        .where.not(product_id: [nil, ""])
        .pluck(:store_id, :product_id)
        .map { |store_id, product_id| [store_id, product_id.to_s] }
        .uniq
    end

    def user_time_range(from_date, to_date)
      time_zone.local(from_date.year, from_date.month, from_date.day).beginning_of_day..
        time_zone.local(to_date.year, to_date.month, to_date.day).end_of_day
    end
  end
end
