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
          order_key: order.order_key,
          external_order_id: order.external_order_id,
          external_order_number: order.external_order_number,
          order_status: order.order_status,
          order_source_status: order.source_status,
          order_source_substatus: order.source_substatus,
          ordered_at: order.ordered_at,
          in_process_at: order.in_process_at,
          order_completed_at: order.completed_at,
          order_cancelled_at: order.cancelled_at,
          buyer_city: order.buyer_city,
          buyer_region: order.buyer_region,
          buyer_country: order.buyer_country,
          payment_method_source: order.payment_method_source,
          is_legal_entity: order.is_legal_entity,
          order_synced_at: order.synced_at,
          fulfillment_id: fulfillment&.id,
          external_fulfillment_id: fulfillment&.external_fulfillment_id,
          fulfillment_key: fulfillment&.fulfillment_key,
          fulfillment_type: fulfillment&.fulfillment_type,
          fulfillment_status: fulfillment&.status,
          fulfillment_source_status: fulfillment&.source_status,
          fulfillment_source_substatus: fulfillment&.source_substatus,
          warehouse_external_id: fulfillment&.warehouse_external_id,
          warehouse_name: fulfillment&.warehouse_name,
          delivery_method_name: fulfillment&.delivery_method_name,
          delivery_type_source: fulfillment&.delivery_type_source,
          cluster_from: fulfillment&.cluster_from,
          cluster_to: fulfillment&.cluster_to,
          tracking_number: fulfillment&.tracking_number,
          shipped_at: fulfillment&.shipped_at,
          delivered_at: fulfillment&.delivered_at,
          fulfillment_cancelled_at: fulfillment&.cancelled_at,
          cancel_reason_source: fulfillment&.cancel_reason_source,
          fulfillment_raw_source_type: fulfillment&.raw_source_type,
          fulfillment_raw_source_id: fulfillment&.raw_source_id,
          fulfillment_synced_at: fulfillment&.synced_at,
          item_id: item.id,
          external_item_id: item.external_item_id,
          sku_code: sku.sku_code,
          platform_sku_id: item.platform_sku_id,
          offer_id: item.offer_id,
          product_name_source: item.product_name_source,
          quantity: item.quantity,
          currency_code: item.currency_code,
          unit_price: item.unit_price,
          old_unit_price: item.old_unit_price,
          discount_amount: item.discount_amount,
          discount_percent: item.discount_percent,
          commission_amount: item.commission_amount,
          commission_percent: item.commission_percent,
          payout: item.payout,
          item_synced_at: item.synced_at
        }
      end
    end
  end
end
