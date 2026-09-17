module ErpAI
  module V2
    class OrdersFullPeriodContext
      def initialize(sku:, period_from:, period_to:, time_zone:)
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @time_zone = time_zone
      end

      def call
        return [] unless binding_predicate

        matching_items.map { |item| row_for(item) }
      end

      private

      attr_reader :sku, :period_from, :period_to, :time_zone

      def matching_items
        Ec::OrderItem
          .includes(:store, :fulfillment, :order)
          .joins(:order)
          .where(ec_orders: { ordered_at: user_date_range })
          .where(binding_predicate)
          .order("ec_orders.ordered_at ASC NULLS LAST", "ec_order_items.id ASC")
      end

      def binding_predicate
        @binding_predicate ||= begin
          table = Ec::OrderItem.arel_table
          predicates = sku.sku_products.filter_map do |product|
            platform_sku_id = product.platform == "wb" ? product.product_id : product.platform_sku_id
            next if platform_sku_id.blank? || !%w[wb ozon].include?(product.platform)

            table[:store_id].eq(product.store_id)
              .and(table[:platform].eq(product.platform))
              .and(table[:platform_sku_id].eq(platform_sku_id.to_s))
          end
          predicates.reduce { |predicate, next_predicate| predicate.or(next_predicate) }
        end
      end

      def user_date_range
        time_zone.local(period_from.year, period_from.month, period_from.day).beginning_of_day..
          time_zone.local(period_to.year, period_to.month, period_to.day).end_of_day
      end

      def row_for(item)
        order = item.order
        fulfillment = item.fulfillment

        {
          platform: item.platform,
          store_id: item.store_id,
          store_name: item.store.store_name,
          order_id: order.id,
          order_status: order.order_status,
          ordered_at: order.ordered_at,
          in_process_at: order.in_process_at,
          order_cancelled_at: order.cancelled_at,
          buyer_city: order.buyer_city,
          buyer_region: order.buyer_region,
          buyer_country: order.buyer_country,
          is_legal_entity: order.is_legal_entity,
          fulfillment_type: fulfillment&.fulfillment_type,
          fulfillment_status: fulfillment&.status,
          warehouse_name: fulfillment&.warehouse_name,
          cluster_from: fulfillment&.cluster_from,
          cluster_to: fulfillment&.cluster_to,
          cancel_reason_source: fulfillment&.cancel_reason_source,
          quantity: item.quantity,
          currency_code: item.currency_code,
          unit_price: item.unit_price
        }
      end
    end
  end
end
