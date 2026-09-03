module SalesFunnelReports
  class SkuCommonDailyTrendQuery
    METRICS = %i[
      product_card_views cart_additions cart_rate orders cart_to_order_rate
      conversions visit_to_conversion_rate net_sales
    ].freeze

    def self.run(sku:, from_date:, to_date:, time_zone: Time.zone)
      new(sku:, from_date:, to_date:, time_zone:).call
    end

    def initialize(sku:, from_date:, to_date:, time_zone:)
      @sku = sku
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @time_zone = time_zone
    end

    def call
      store_trends = SkuDailyTrendQuery.new(sku:, from_date:, to_date:).call
      funnel_by_date = aggregate_funnel(store_trends)
      orders_by_date = aggregate_orders
      rows = (from_date..to_date).map do |date|
        funnel = funnel_by_date[date.iso8601]
        orders = orders_by_date[date]
        build_row(date, funnel, orders)
      end
      { rows:, metrics: METRICS }
    end

    private

    attr_reader :sku, :from_date, :to_date, :time_zone

    def aggregate_funnel(store_trends)
      store_trends.flat_map do |trend|
        trend[:rows].map { |row| [row[:date], trend[:platform], row[:values]] }
      end.group_by(&:first).transform_values do |entries|
        {
          views: entries.sum { |_date, platform, values| (platform == "wb" ? values[:open_card] : values[:hits_view_pdp]).to_d },
          carts: entries.sum { |_date, platform, values| (platform == "wb" ? values[:add_to_cart] : values[:hits_tocart_pdp]).to_d },
          orders: entries.sum { |_date, platform, values| (platform == "wb" ? values[:orders] : values[:ordered_units]).to_d },
          present: entries.any? { |_date, _platform, values| values.values.any?(&:present?) }
        }
      end
    end

    def aggregate_orders
      from_time = time_zone.local(from_date.year, from_date.month, from_date.day).beginning_of_day
      to_time = time_zone.local(to_date.year, to_date.month, to_date.day).end_of_day
      Ec::OrderItem.joins(:order).joins(SkuFunnelAnalysisQuery::ORDER_ITEM_JOIN)
        .where(ec_sku_products: { sku_code: sku.sku_code })
        .where(ec_orders: { ordered_at: from_time..to_time })
        .select("ec_order_items.quantity, ec_orders.ordered_at AS matched_ordered_at, ec_orders.order_status AS matched_order_status")
        .each_with_object(Hash.new { |hash, key| hash[key] = { conversions: 0, net_sales: 0, present: false } }) do |item, result|
          date = item.matched_ordered_at.in_time_zone(time_zone).to_date
          result[date][:present] = true
          result[date][:conversions] += item.quantity if item.matched_order_status.in?(%w[delivered returned])
          result[date][:net_sales] += item.quantity if item.matched_order_status == "delivered"
        end
    end

    def build_row(date, funnel, order_values)
      views = funnel&.fetch(:views, 0).to_d
      carts = funnel&.fetch(:carts, 0).to_d
      orders = funnel&.fetch(:orders, 0).to_d
      conversions = order_values&.fetch(:conversions, 0).to_d
      {
        date: date.iso8601,
        values: {
          product_card_views: funnel&.fetch(:present, false) ? views.to_f : nil,
          cart_additions: funnel&.fetch(:present, false) ? carts.to_f : nil,
          cart_rate: percent(carts, views),
          orders: funnel&.fetch(:present, false) ? orders.to_f : nil,
          cart_to_order_rate: percent(orders, carts),
          conversions: order_values&.fetch(:present, false) ? conversions.to_f : nil,
          visit_to_conversion_rate: order_values&.fetch(:present, false) ? percent(conversions, views) : nil,
          net_sales: order_values&.fetch(:present, false) ? order_values[:net_sales].to_f : nil
        }
      }
    end

    def percent(numerator, denominator)
      return nil unless denominator.to_d.positive?

      (numerator.to_d / denominator.to_d * 100).round(2).to_f
    end
  end
end
