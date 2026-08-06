module Ec
  module Returns
    class WbNormalizer < BaseNormalizer
      private

      def platform
        "wb"
      end

      def store_lookup
        { platform: platform, wb_raw_account_id: raw_record.account_id }
      end

      def return_key
        raw_record.shk_id.to_s
      end

      def item_key
        raw_record.shk_id.to_s
      end

      def return_attributes
        {
          order: order,
          return_type: order&.order_cancelled? ? "cancellation_return" : "customer_return",
          process_status: process_status,
          inventory_location: inventory_location,
          inventory_condition: "unknown",
          refund_status: "none",
          external_return_id: raw_record.shk_id.to_s,
          external_order_id: raw_record.order_id&.to_s,
          external_order_number: raw_record.srid,
          requested_at: raw_record.order_dt,
          returned_to_seller_at: raw_record.completed_dt,
          completed_at: raw_record.completed_dt,
          source_status: raw_record.status,
          source_substatus: raw_record.reason,
          source_payload: raw_record.attributes.except("id"),
          synced_at: raw_record.synced_at
        }
      end

      def process_status
        return "completed" if raw_record.completed_dt.present?
        return "ready_for_seller_pickup" if raw_record.ready_to_return_dt.present?

        "unknown"
      end

      def inventory_location
        return "platform_return_warehouse" if raw_record.ready_to_return_dt.present? && raw_record.completed_dt.blank?

        "unknown"
      end

      def find_order
        Ec::Order.where(platform: platform, store_id: store.id)
          .where(
            "external_order_id = :external_id OR external_order_number = :external_number",
            external_id: raw_record.order_id&.to_s,
            external_number: raw_record.srid
          ).first
      end

      def find_sku_product
        Ec::SkuProduct.find_by(
          store_id: store.id,
          platform: platform,
          product_id: raw_record.nm_id&.to_s
        )
      end

      def platform_sku_id
        nil
      end

      def product_id
        raw_record.nm_id&.to_s
      end

      def offer_id
        sku_product&.offer_id
      end

      def order_item_platform_sku_id
        product_id
      end

      def quantity
        1
      end

      def item_metadata
        {
          barcode: raw_record.barcode,
          sticker_id: raw_record.sticker_id,
          destination_office_id: raw_record.dst_office_id,
          destination_office_address: raw_record.dst_office_address
        }
      end
    end
  end
end
