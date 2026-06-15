module Ec
  module OrderImport
    class Ozon
      STATUS_MAP = {
        "awaiting_registration" => "processing",
        "acceptance_in_progress" => "processing",
        "awaiting_approve" => "processing",
        "awaiting_packaging" => "processing",
        "awaiting_deliver" => "processing",
        "arbitration" => "processing",
        "client_arbitration" => "processing",
        "delivering" => "shipped",
        "driver_pickup" => "shipped",
        "delivered" => "delivered",
        "cancelled" => "cancelled",
        "not_accepted" => "cancelled",
        "sent_by_seller" => "shipped"
      }.freeze
      CANCELLATION_TIME_KEYS = %w[cancelled_at canceled_at cancel_date cancelled_date cancellation_date].freeze

      def call(synced_since: nil)
        total = 0
        fbo_scope = RawOzon::PostingFbo.includes(:account)
        fbo_scope = fbo_scope.where("raw_ozon_postings_fbo.synced_at >= ?", synced_since) if synced_since
        fbo_scope.find_each do |posting|
          total += import_posting(posting, "fbo", "RawOzon::PostingFbo")
        end

        fbs_scope = RawOzon::PostingFbs.includes(:account)
        fbs_scope = fbs_scope.where("raw_ozon_postings_fbs.synced_at >= ?", synced_since) if synced_since
        fbs_scope.find_each do |posting|
          total += import_posting(posting, "fbs", "RawOzon::PostingFbs")
        end
        total
      end

      private

      def import_posting(posting, type, source_type)
        store = store_for(posting.account)
        return 0 unless store

        order = upsert_order(posting, store, type)
        fulfillment = upsert_fulfillment(posting, store, order, type, source_type)
        import_items(posting, store, order, fulfillment, type)
        upsert_source_link(order, fulfillment, nil, source_type, posting.id, posting.posting_number)
        1
      end

      def store_for(account)
        Ec::Store.find_by(platform: "ozon", ozon_raw_account_id: account.id) ||
          Ec::Store.find_by(platform: "ozon", ozon_client_id: account.client_id)
      end

      def upsert_order(posting, store, type)
        order_key = "ozon:#{store.id}:#{posting.order_number.presence || posting.order_id || posting.posting_number}"
        order = Ec::Order.find_or_initialize_by(platform: "ozon", store: store, order_key: order_key)
        order.assign_attributes(
          external_order_id: posting.order_id&.to_s,
          external_order_number: posting.order_number.presence || posting.posting_number,
          order_status: normalized_status(posting.status),
          source_status: posting.status,
          source_substatus: posting.substatus,
          ordered_at: posting.created_at,
          in_process_at: posting.in_process_at,
          completed_at: completed_at_for(posting, type),
          cancelled_at: cancelled_at_for(posting),
          buyer_city: posting.analytics_data&.dig("city"),
          payment_method_source: posting.analytics_data&.dig("payment_type_group_name"),
          is_legal_entity: posting.analytics_data&.dig("is_legal") || false,
          source_payload: posting.raw_json,
          synced_at: posting.synced_at
        )
        order.save!
        order
      end

      def upsert_fulfillment(posting, store, order, type, source_type)
        fulfillment_key = "ozon:#{store.id}:#{posting.posting_number}"
        fulfillment = Ec::OrderFulfillment.find_or_initialize_by(platform: "ozon", store: store, fulfillment_key: fulfillment_key)
        fulfillment.assign_attributes(
          order: order,
          external_fulfillment_id: posting.posting_number,
          fulfillment_type: type,
          status: normalized_status(posting.status),
          source_status: posting.status,
          source_substatus: posting.substatus,
          warehouse_name: posting.analytics_data&.dig("warehouse_name"),
          warehouse_external_id: posting.analytics_data&.dig("warehouse_id")&.to_s,
          delivery_method_name: type == "fbs" ? posting.delivery_method_name : nil,
          delivery_type_source: posting.analytics_data&.dig("delivery_type"),
          tracking_number: type == "fbs" ? posting.tracking_number : nil,
          shipped_at: type == "fbs" ? posting.shipment_date : nil,
          delivered_at: completed_at_for(posting, type),
          cancelled_at: cancelled_at_for(posting),
          cancel_reason_source: posting.respond_to?(:cancel_reason_id) ? posting.cancel_reason_id&.to_s : nil,
          raw_source_type: source_type,
          raw_source_id: posting.id,
          synced_at: posting.synced_at
        )
        fulfillment.save!
        fulfillment
      end

      def import_items(posting, store, order, fulfillment, type)
        existing = Ec::OrderItem.where(order: order, fulfillment: fulfillment)
        source_items = RawOzon::PostingItem.where(
          account_id: posting.account_id,
          posting_number: posting.posting_number,
          posting_type: type
        ).order(:id)

        existing.delete_all
        source_items.each do |item|
          fin = financial_product(posting, item)
          product = product_for(posting.account_id, item)
          sku_product = sku_product_for(store, product&.ozon_product_id)
          Ec::OrderItem.create!(
            order: order,
            fulfillment: fulfillment,
            platform: "ozon",
            store: store,
            external_item_id: "#{posting.posting_number}:#{item.ozon_sku || item.offer_id}",
            platform_sku_id: item.ozon_sku&.to_s,
            offer_id: item.offer_id,
            sku_code: sku_product&.sku_code,
            product_name_source: item.name,
            quantity: item.quantity,
            unit_price: item.price,
            old_unit_price: item.old_price,
            currency_code: item.currency_code,
            payout: fin["payout"] || item.payout,
            commission_amount: fin["commission_amount"] || item.commission_amount,
            commission_percent: fin["commission_percent"] || item.commission_percent,
            discount_amount: fin["total_discount_value"],
            discount_percent: fin["total_discount_percent"],
            item_payload: item.raw_json,
            synced_at: item.synced_at || posting.synced_at
          )
        end
      end

      def financial_product(posting, item)
        Array(posting.financial_data&.dig("products")).find do |product|
          product["product_id"].to_s == item.ozon_sku.to_s
        end || {}
      end

      def product_for(account_id, item)
        scope = RawOzon::Product.where(account_id: account_id)
        scope.find_by("raw_json ->> 'sku' = ?", item.ozon_sku.to_s) ||
          scope.find_by(offer_id: item.offer_id)
      end

      def sku_product_for(store, product_id)
        return unless product_id

        Ec::SkuProduct.find_by(store: store, product_id: product_id.to_s)
      end

      def upsert_source_link(order, fulfillment, item, source_type, source_id, source_key)
        link = Ec::OrderSourceLink.find_or_initialize_by(
          source_type: source_type,
          source_id: source_id,
          source_role: "primary"
        )
        link.assign_attributes(
          order: order,
          fulfillment: fulfillment,
          item: item,
          platform: "ozon",
          source_key: source_key,
          synced_at: fulfillment.synced_at
        )
        link.save!
      end

      def normalized_status(status)
        STATUS_MAP.fetch(status.to_s, "unknown")
      end

      def completed_at_for(posting, type)
        return unless normalized_status(posting.status) == "delivered"

        type == "fbs" ? posting.delivering_date : posting.fact_delivery_date
      end

      def cancelled_at_for(posting)
        return unless normalized_status(posting.status) == "cancelled"

        [posting.raw_json, posting.raw_json&.dig("cancellation"), posting.try(:cancellation)].filter_map do |payload|
          cancellation_time_from(payload)
        end.first
      end

      def cancellation_time_from(payload)
        return unless payload.respond_to?(:[])

        CANCELLATION_TIME_KEYS.each do |key|
          value = payload[key] || payload[key.to_sym]
          return value if value.present?
        end
        nil
      end
    end
  end
end
