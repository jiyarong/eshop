module Ec
  class OperatorSkuWeeklyOrderMetricsQuery
    STATUSES = { ordered: :all, signed: %w[delivered], cancelled: %w[cancelled], returned: %w[returned], in_transit: %w[pending processing shipped] }.freeze

    def initialize(sku_codes:, from_date:, to_date:, time_zone:)
      @codes = Array(sku_codes).map(&:to_s)
      @from = time_zone.local(from_date.year, from_date.month, from_date.day).beginning_of_day
      @to = time_zone.local(to_date.year, to_date.month, to_date.day).end_of_day
      @previous_from = @from - 1.week
      @previous_to = @from - 1.second
    end

    def call
      result = @codes.index_with { empty_metrics }
      previous = @codes.index_with { empty_metrics }
      rows = Ec::OrderItem.includes(:order).joins(:order).joins("INNER JOIN ec_sku_products sp ON sp.store_id = ec_order_items.store_id AND sp.platform = ec_order_items.platform AND ((sp.platform = 'ozon' AND sp.platform_sku_id = ec_order_items.platform_sku_id) OR (sp.platform = 'wb' AND sp.product_id = ec_order_items.platform_sku_id))").where(sp: { sku_code: @codes }).where(ec_orders: { ordered_at: @previous_from..@to }).select("ec_order_items.*, sp.sku_code AS internal_sku_code")
      rows.group_by { |item| item.internal_sku_code.to_s }.each do |code, items|
        weighted_days = 0.to_d
        weighted_quantity = 0
        items.each do |item|
          target = item.order.ordered_at >= @from ? result[code] : previous[code]
          status = item.order.order_status
          qty = item.quantity.to_i
          target[:ordered] += qty
          target[:signed] += qty if status == "delivered"
          target[:cancelled] += qty if status == "cancelled"
          target[:returned] += qty if status == "returned"
          target[:in_transit] += qty if %w[pending processing shipped].include?(status)
          if target.equal?(result[code]) && item.order.completed_at.present?
            weighted_days += ((item.order.completed_at - item.order.ordered_at) / 1.day) * qty
            weighted_quantity += qty
          end
        end
        result[code][:delivery_days] = (weighted_days / weighted_quantity).round(2) if weighted_quantity.positive?
      end
      result.each do |code, metrics|
        metrics[:comparisons] = STATUSES.keys.index_with { |key| comparison(metrics[key], previous[code][key], favorable_up: key.in?([:ordered, :signed])) }
      end
      result
    end

    private

    def empty_metrics
      { ordered: 0, signed: 0, cancelled: 0, returned: 0, in_transit: 0, delivery_days: nil }
    end

    def comparison(current, previous, favorable_up:)
      return { current:, previous:, delta_pct: nil, semantic: "neutral" } if previous.zero?

      delta = (((current - previous).to_d / previous) * 100).round(2)
      favorable = favorable_up ? delta.positive? : delta.negative?
      { current:, previous:, delta_pct: delta, semantic: delta.zero? ? "neutral" : (favorable ? "positive" : "negative") }
    end
  end
end
