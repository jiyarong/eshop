module Ec
  class OperatorSkuSalesFunnelMetricsQuery
    METRICS = %i[
      product_card_views cart_additions cart_rate orders cart_to_order_rate
      cancellations conversions visit_to_conversion_rate net_sales
    ].freeze
    NEGATIVE_COMPARISON_METRICS = %i[cancellations].freeze
    ORDER_ITEM_JOIN = SalesFunnelReports::SkuFunnelAnalysisQuery::ORDER_ITEM_JOIN

    def initialize(skus:, from_date:, to_date:, time_zone:)
      @skus = skus.to_a
      @sku_codes = @skus.map(&:sku_code)
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @time_zone = time_zone
    end

    def call
      return {} if @skus.empty?

      products = Ec::SkuProduct.includes(:store)
        .where(sku_code: @sku_codes, platform: %w[wb ozon])
        .select { |product| product.store&.is_active? }
      raw = load_raw_totals(products)
      orders = load_order_totals(products)

      @skus.index_with do |sku|
        current = aggregate(sku.sku_code, :current, products, raw, orders)
        previous = aggregate(sku.sku_code, :previous, products, raw, orders)
        METRICS.index_with do |metric|
          { value: current[metric], comparison: comparison(current[metric], previous[metric], metric: metric) }
        end
      end
    end

    private

    def load_raw_totals(products)
      result = Hash.new { |hash, key| hash[key] = empty_funnel_totals }
      wb_products = products.select { |product| product.platform == "wb" }.index_by { |product| [product.store.wb_raw_account_id, product.product_id.to_s] }
      ozon_products = products.select { |product| product.platform == "ozon" }.index_by { |product| [product.store.ozon_raw_account_id, product.platform_sku_id.to_s] }

      RawWb::SalesFunnelDaily.where(account_id: wb_products.keys.map(&:first).compact.uniq, stat_date: full_range).find_each do |record|
        product = wb_products[[record.account_id, record.nm_id.to_s]]
        add_raw(result, product, record.stat_date, record.open_card, record.add_to_cart, record.orders, record.cancel_count) if product
      end
      RawOzon::SalesFunnelDaily.where(account_id: ozon_products.keys.map(&:first).compact.uniq, stat_date: full_range).find_each do |record|
        product = ozon_products[[record.account_id, record.sku.to_s]]
        add_raw(result, product, record.stat_date, record.hits_view_pdp, record.hits_tocart_pdp, record.ordered_units, record.cancellations) if product
      end
      result
    end

    def load_order_totals(products)
      result = Hash.new { |hash, key| hash[key] = { conversions: 0, net_sales: 0, present: false } }
      product_ids = products.map(&:id)
      return result if product_ids.empty?

      Ec::OrderItem.joins(:order).joins(ORDER_ITEM_JOIN)
        .where(ec_sku_products: { id: product_ids })
        .where(ec_orders: { ordered_at: local_day(full_range.begin).beginning_of_day..local_day(full_range.end).end_of_day })
        .pluck("ec_sku_products.sku_code", "ec_orders.ordered_at", "ec_orders.order_status", "ec_order_items.quantity")
        .each do |sku_code, ordered_at, status, quantity|
          totals = result[[sku_code.to_s, period_key(ordered_at.in_time_zone(@time_zone).to_date)]]
          totals[:conversions] += quantity.to_i if status.in?(%w[delivered returned])
          totals[:net_sales] += quantity.to_i if status == "delivered"
          totals[:present] = true
        end
      result
    end

    def add_raw(result, product, date, views, carts, orders, cancellations)
      totals = result[[product.id, period_key(date)]]
      totals[:product_card_views] += views.to_d
      totals[:cart_additions] += carts.to_d
      totals[:orders] += orders.to_d
      totals[:cancellations] += cancellations.to_d
      totals[:present] = true
    end

    def aggregate(sku_code, period, products, raw, orders)
      funnel = products.select { |product| product.sku_code == sku_code }.map { |product| raw[[product.id, period]] }
      order = orders[[sku_code, period]]
      views = funnel.sum { |row| row[:product_card_views] }
      carts = funnel.sum { |row| row[:cart_additions] }
      ordered = funnel.sum { |row| row[:orders] }
      cancellations = funnel.sum { |row| row[:cancellations] }
      funnel_present = funnel.any? { |row| row[:present] }

      {
        product_card_views: funnel_present ? views : nil,
        cart_additions: funnel_present ? carts : nil,
        cart_rate: funnel_present ? percent(carts, views) : nil,
        orders: funnel_present ? ordered : nil,
        cart_to_order_rate: funnel_present ? percent(ordered, carts) : nil,
        cancellations: funnel_present ? cancellations : nil,
        conversions: order[:present] ? order[:conversions] : nil,
        visit_to_conversion_rate: order[:present] && funnel_present ? percent(order[:conversions], views) : nil,
        net_sales: order[:present] ? order[:net_sales] : nil
      }
    end

    def empty_funnel_totals
      {
        product_card_views: 0.to_d,
        cart_additions: 0.to_d,
        orders: 0.to_d,
        cancellations: 0.to_d,
        present: false
      }
    end

    def full_range
      (@from_date - period_days.days)..@to_date
    end

    def period_days
      (@to_date - @from_date).to_i + 1
    end

    def period_key(date)
      date.in?(@from_date..@to_date) ? :current : :previous
    end

    def local_day(date)
      @time_zone.local(date.year, date.month, date.day)
    end

    def percent(numerator, denominator)
      return nil unless denominator.to_d.positive?

      (numerator.to_d / denominator.to_d * 100).round(2)
    end

    def comparison(current, previous, metric:)
      return if current.nil? || previous.nil? || previous.to_d.zero?

      delta = ((current.to_d - previous.to_d) / previous.to_d.abs * 100).round(2)
      favorable = NEGATIVE_COMPARISON_METRICS.include?(metric) ? delta.negative? : delta.positive?
      {
        delta_pct: delta,
        trend: delta.positive? ? "up" : (delta.negative? ? "down" : "flat"),
        semantic: delta.zero? ? "neutral" : (favorable ? "positive" : "negative")
      }
    end

  end
end
