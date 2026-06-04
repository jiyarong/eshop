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

      def call
        total = 0
        RawOzon::PostingFbo.includes(:account).find_each do |posting|
          total += import_posting(posting, "fbo", "RawOzon::PostingFbo")
        end
        RawOzon::PostingFbs.includes(:account).find_each do |posting|
          total += import_posting(posting, "fbs", "RawOzon::PostingFbs")
        end
        total
      end

      private

      def import_posting(posting, type, source_type)
        store = store_for(posting.account)
        return 0 unless store

        order = upsert_order(posting, store)
        fulfillment = upsert_fulfillment(posting, store, order, type, source_type)
        import_items(posting, store, order, fulfillment, type)
        upsert_source_link(order, fulfillment, nil, source_type, posting.id, posting.posting_number)
        1
      end

      def store_for(account)
        Ec::Store.find_by(platform: "ozon", ozon_raw_account_id: account.id) ||
          Ec::Store.find_by(platform: "ozon", ozon_client_id: account.client_id)
      end

      def upsert_order(posting, store)
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
          delivered_at: type == "fbs" ? posting.delivering_date : posting.fact_delivery_date,
          cancelled_at: nil,
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
          Ec::OrderItem.create!(
            order: order,
            fulfillment: fulfillment,
            platform: "ozon",
            store: store,
            external_item_id: "#{posting.posting_number}:#{item.ozon_sku || item.offer_id}",
            platform_sku_id: item.ozon_sku&.to_s,
            offer_id: item.offer_id,
            sku_code: Ec::Sku.find_by(sku_code: item.offer_id&.upcase)&.sku_code,
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
    end
  end
end
