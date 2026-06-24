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

      def call(synced_since: nil)
        total = 0
        raw_orders_for_import(synced_since).find_each do |raw_order|
          total += import_order(raw_order)
        end
        stats_orders_for_import(synced_since).find_each do |stats_order|
          total += import_stats_order(stats_order)
        end
        total
      end

      private

      def raw_orders_for_import(synced_since)
        scope = RawWb::Order.includes(:account)
        return scope unless synced_since

        scope.where("raw_wb_orders.synced_at >= ?", synced_since)
      end

      def stats_orders_for_import(synced_since)
        scope = RawWb::StatsOrder.includes(:account).where.not(srid: [nil, ""])
        return scope unless synced_since

        scope.where("raw_wb_stats_orders.synced_at >= ?", synced_since)
      end

      def import_order(raw_order)
        store = store_for(raw_order.account)
        return 0 unless store

        order = upsert_order(raw_order, store)
        fulfillment = upsert_fulfillment(raw_order, store, order)
        import_item(raw_order, store, order, fulfillment)
        upsert_source_link(order, fulfillment, raw_order)
        1
      end

      def import_stats_order(stats_order)
        store = store_for(stats_order.account)
        return 0 unless store

        order = upsert_order_from_stats(stats_order, store)
        fulfillment = upsert_fulfillment_from_stats(stats_order, store, order)
        import_item_from_stats(stats_order, store, order, fulfillment)
        upsert_stats_source_link(order, fulfillment, stats_order)
        1
      end

      def store_for(account)
        Ec::Store.find_by(platform: "wb", wb_raw_account_id: account.id)
      end

      def upsert_order(raw_order, store)
        external_number = order_identifier(raw_order)
        order_key = wb_order_key(store, external_number)
        stats_sale = stats_record_for(RawWb::StatsSale, raw_order)
        stats_order = stats_record_for(RawWb::StatsOrder, raw_order)
        order = Ec::Order.find_or_initialize_by(platform: "wb", store: store, order_key: order_key)
        order.assign_attributes(
          external_order_id: raw_order.srid.presence || raw_order.wb_order_id.to_s,
          external_order_number: external_number,
          order_status: normalized_status(raw_order),
          source_status: raw_order.wb_status,
          source_substatus: raw_order.supplier_status,
          ordered_at: raw_order.created_at,
          in_process_at: raw_order.updated_at,
          completed_at: stats_sale&.sale_date,
          cancelled_at: stats_order&.is_cancel? ? stats_order.cancel_date : nil,
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

      def upsert_order_from_stats(stats_order, store)
        external_number = order_identifier(stats_order)
        order_key = wb_order_key(store, external_number)
        stats_sale = stats_record_for(RawWb::StatsSale, stats_order)
        order = order_from_stats(stats_order, store, order_key)
        order.assign_attributes(
          order_key: order_key,
          external_order_id: stats_order.srid,
          external_order_number: external_number,
          order_status: stats_order.is_cancel? ? "cancelled" : "processing",
          source_status: stats_order.order_type,
          source_substatus: stats_order.is_cancel? ? "cancelled" : nil,
          ordered_at: stats_order.order_date,
          in_process_at: stats_order.last_change_date,
          completed_at: stats_sale&.sale_date,
          cancelled_at: stats_order.is_cancel? ? stats_order.cancel_date : nil,
          buyer_city: stats_order.oblast,
          payment_method_source: nil,
          source_payload: stats_order.attributes.slice(
            "srid", "g_number", "order_type", "is_cancel", "cancel_date"
          ),
          synced_at: stats_order.synced_at
        )
        order.save!
        order
      end

      def order_from_stats(stats_order, store, order_key)
        Ec::Order.find_by(platform: "wb", store: store, order_key: order_key) ||
          Ec::Order.new(platform: "wb", store: store, order_key: order_key)
      end

      def order_identifier(source)
        source.srid.presence || (source.wb_order_id.to_s if source.respond_to?(:wb_order_id))
      end

      def wb_order_key(store, identifier)
        "wb:#{store.id}:#{identifier}"
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

      def upsert_fulfillment_from_stats(stats_order, store, order)
        fulfillment_id = stats_order.srid
        fulfillment_key = "wb:#{store.id}:#{fulfillment_id}"
        fulfillment = order.fulfillments.first ||
          Ec::OrderFulfillment.find_or_initialize_by(platform: "wb", store: store, fulfillment_key: fulfillment_key)
        fulfillment.assign_attributes(
          order: order,
          external_fulfillment_id: fulfillment_id,
          fulfillment_key: fulfillment.fulfillment_key.presence || fulfillment_key,
          fulfillment_type: fulfillment_type_from_warehouse_type(stats_order.warehouse_type),
          status: stats_order.is_cancel? ? "cancelled" : "processing",
          source_status: stats_order.order_type,
          source_substatus: stats_order.is_cancel? ? "cancelled" : nil,
          warehouse_name: stats_order.warehouse_name,
          delivery_type_source: stats_order.order_type,
          raw_source_type: "RawWb::StatsOrder",
          raw_source_id: stats_order.id,
          synced_at: stats_order.synced_at
        )
        fulfillment.save!
        fulfillment
      end

      def import_item(raw_order, store, order, fulfillment)
        sku_product = sku_product_for(store, raw_order.nm_id)
        Ec::OrderItem.where(order: order, fulfillment: fulfillment).delete_all
        Ec::OrderItem.create!(
          order: order,
          fulfillment: fulfillment,
          platform: "wb",
          store: store,
          external_item_id: raw_order.wb_order_id.to_s,
          platform_sku_id: raw_order.nm_id&.to_s,
          offer_id: raw_order.article,
          sku_code: sku_product&.sku_code,
          product_name_source: raw_order.article,
          quantity: 1,
          unit_price: raw_order.converted_price || raw_order.price,
          currency_code: CURRENCY_MAP.fetch(raw_order.currency_code.to_i, raw_order.currency_code&.to_s),
          item_payload: raw_order.attributes.slice("nm_id", "article", "barcode", "price", "converted_price"),
          synced_at: raw_order.synced_at
        )
      end

      def import_item_from_stats(stats_order, store, order, fulfillment)
        sku_product = sku_product_for(store, stats_order.nm_id)
        Ec::OrderItem.where(order: order).delete_all
        Ec::OrderItem.create!(
          order: order,
          fulfillment: fulfillment,
          platform: "wb",
          store: store,
          external_item_id: stats_order.srid,
          platform_sku_id: stats_order.nm_id&.to_s,
          offer_id: stats_order.supplier_article,
          sku_code: sku_product&.sku_code,
          product_name_source: stats_order.supplier_article,
          quantity: 1,
          unit_price: stats_order.total_price,
          currency_code: "RUB",
          item_payload: stats_order.attributes.slice(
            "nm_id", "supplier_article", "barcode", "total_price", "discount_percent"
          ),
          synced_at: stats_order.synced_at
        )
      end

      def fulfillment_type_from_warehouse_type(warehouse_type)
        case warehouse_type
        when "Склад WB"
          "fbw"
        when "Склад продавца"
          "fbs"
        else
          "unknown"
        end
      end

      def sku_product_for(store, product_id)
        return unless product_id

        Ec::SkuProduct.find_by(store: store, product_id: product_id.to_s)
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

      def upsert_stats_source_link(order, fulfillment, stats_order)
        link = Ec::OrderSourceLink.find_or_initialize_by(
          source_type: "RawWb::StatsOrder",
          source_id: stats_order.id,
          source_role: "primary"
        )
        link.assign_attributes(
          order: order,
          fulfillment: fulfillment,
          platform: "wb",
          source_key: stats_order.srid,
          synced_at: stats_order.synced_at
        )
        link.save!
      end

      def normalized_status(raw_order)
        return "cancelled" if raw_order.wb_status.to_s == "cancelled" || raw_order.supplier_status.to_s.include?("cancel")

        STATUS_MAP[raw_order.supplier_status.to_s] ||
          STATUS_MAP[raw_order.wb_status.to_s] ||
          "unknown"
      end

      def stats_record_for(model, raw_order)
        scope = model.where(account_id: raw_order.account_id)
        if raw_order.srid.present?
          record = scope.find_by(srid: raw_order.srid)
          return record if record
        end

        return unless raw_order.g_number.present?

        scope.where(g_number: raw_order.g_number).order(:id).first
      end
    end
  end
end
