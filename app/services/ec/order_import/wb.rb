module Ec
  module OrderImport
    class Wb
      STATUS_MAP = {
        "new" => "processing",
        "confirm" => "processing",
        "complete" => "delivered",
        "cancel" => "cancelled",
        "cancelled" => "cancelled"
      }.freeze

      CURRENCY_MAP = {
        643 => "RUB",
        933 => "BYN",
        840 => "USD",
        978 => "EUR"
      }.freeze

      def call
        total = 0
        RawWb::Order.includes(:account).find_each do |raw_order|
          total += import_order(raw_order)
        end
        total
      end

      private

      def import_order(raw_order)
        store = store_for(raw_order.account)
        return 0 unless store

        order = upsert_order(raw_order, store)
        fulfillment = upsert_fulfillment(raw_order, store, order)
        import_item(raw_order, store, order, fulfillment)
        upsert_source_link(order, fulfillment, raw_order)
        1
      end

      def store_for(account)
        Ec::Store.find_by(platform: "wb", wb_raw_account_id: account.id)
      end

      def upsert_order(raw_order, store)
        external_number = raw_order.g_number.presence || raw_order.srid.presence || raw_order.wb_order_id.to_s
        order_key = "wb:#{store.id}:#{external_number}"
        order = Ec::Order.find_or_initialize_by(platform: "wb", store: store, order_key: order_key)
        order.assign_attributes(
          external_order_id: raw_order.srid.presence || raw_order.wb_order_id.to_s,
          external_order_number: external_number,
          order_status: normalized_status(raw_order),
          source_status: raw_order.wb_status,
          source_substatus: raw_order.supplier_status,
          ordered_at: raw_order.created_at,
          in_process_at: raw_order.updated_at,
          buyer_city: raw_order.wb_office,
          payment_method_source: nil,
          source_payload: raw_order.attributes.slice(
            "wb_order_id", "order_uid", "srid", "g_number", "supplier_status", "wb_status"
          ),
          synced_at: raw_order.synced_at
        )
        order.save!
        order
      end

      def upsert_fulfillment(raw_order, store, order)
        fulfillment_id = raw_order.wb_order_id.to_s
        fulfillment_key = "wb:#{store.id}:#{fulfillment_id}"
        fulfillment = Ec::OrderFulfillment.find_or_initialize_by(platform: "wb", store: store, fulfillment_key: fulfillment_key)
        fulfillment.assign_attributes(
          order: order,
          external_fulfillment_id: fulfillment_id,
          fulfillment_type: raw_order.delivery_type.presence_in(%w[fbo fbs fba fbm]) || "unknown",
          status: normalized_status(raw_order),
          source_status: raw_order.wb_status,
          source_substatus: raw_order.supplier_status,
          warehouse_name: raw_order.wb_office,
          delivery_type_source: raw_order.delivery_type,
          raw_source_type: "RawWb::Order",
          raw_source_id: raw_order.id,
          synced_at: raw_order.synced_at
        )
        fulfillment.save!
        fulfillment
      end

      def import_item(raw_order, store, order, fulfillment)
        Ec::OrderItem.where(order: order, fulfillment: fulfillment).delete_all
        Ec::OrderItem.create!(
          order: order,
          fulfillment: fulfillment,
          platform: "wb",
          store: store,
          external_item_id: raw_order.wb_order_id.to_s,
          platform_sku_id: raw_order.nm_id&.to_s,
          offer_id: raw_order.article,
          sku_code: Ec::Sku.find_by(sku_code: raw_order.article&.upcase)&.sku_code,
          product_name_source: raw_order.article,
          quantity: 1,
          unit_price: raw_order.converted_price || raw_order.price,
          currency_code: CURRENCY_MAP.fetch(raw_order.currency_code.to_i, raw_order.currency_code&.to_s),
          item_payload: raw_order.attributes.slice("nm_id", "article", "barcode", "price", "converted_price"),
          synced_at: raw_order.synced_at
        )
      end

      def upsert_source_link(order, fulfillment, raw_order)
        link = Ec::OrderSourceLink.find_or_initialize_by(
          source_type: "RawWb::Order",
          source_id: raw_order.id,
          source_role: "primary"
        )
        link.assign_attributes(
          order: order,
          fulfillment: fulfillment,
          platform: "wb",
          source_key: raw_order.wb_order_id.to_s,
          synced_at: raw_order.synced_at
        )
        link.save!
      end

      def normalized_status(raw_order)
        return "cancelled" if raw_order.wb_status.to_s == "cancelled" || raw_order.supplier_status.to_s.include?("cancel")

        STATUS_MAP[raw_order.supplier_status.to_s] ||
          STATUS_MAP[raw_order.wb_status.to_s] ||
          "unknown"
      end
    end
  end
end
