module Ec
  module Returns
    class OzonNormalizer < BaseNormalizer
      STATUS_MAP = {
        "OnSellerApproval" => [ "requested", "customer" ],
        "WaitingShipment" => [ "approved", "customer" ],
        "MovingToOzon" => [ "moving_to_platform", "return_transit" ],
        "ReturnedToOzon" => [ "at_platform", "platform_return_warehouse" ],
        "MovingToSeller" => [ "moving_to_seller", "seller_return_transit" ],
        "ReadyForSeller" => [ "ready_for_seller_pickup", "platform_return_warehouse" ],
        "MoneyReturned" => [ "completed", "unknown" ],
        "PartialCompensationReturned" => [ "completed", "unknown" ]
      }.freeze

      private

      def platform
        "ozon"
      end

      def store_lookup
        { platform: platform, ozon_raw_account_id: raw_record.account_id }
      end

      def return_key
        raw_record.return_id.to_s
      end

      def item_key
        raw_record.return_id.to_s
      end

      def return_attributes
        process_status, inventory_location = STATUS_MAP.fetch(source_status, [ "unknown", "unknown" ])

        {
          order: order,
          return_type: raw_record.return_type == "Cancellation" ? "cancellation_return" : "customer_return",
          process_status: process_status,
          inventory_location: inventory_location,
          inventory_condition: "unknown",
          refund_status: refund_status,
          external_return_id: raw_record.return_id.to_s,
          external_order_id: raw_record.order_id&.to_s,
          external_order_number: raw_record.order_number,
          external_posting_number: raw_record.posting_number,
          requested_at: raw_record.return_date,
          returned_to_platform_at: source_status == "ReturnedToOzon" ? raw_record.final_moment : nil,
          completed_at: process_status == "completed" ? raw_record.visual_change_moment : nil,
          source_status: source_status,
          source_substatus: raw_record.return_reason_name,
          source_payload: raw_record.raw_json || {},
          synced_at: raw_record.synced_at
        }
      end

      def source_status
        @source_status ||= begin
          payload_status = raw_record.raw_json&.dig("visual", "status")
          if payload_status.is_a?(Hash)
            payload_status["sys_name"] || payload_status[:sys_name]
          elsif payload_status.is_a?(String)
            payload_status
          end || raw_record.visual_status.to_s
        end
      end

      def refund_status
        case source_status
        when "MoneyReturned" then "full"
        when "PartialCompensationReturned" then "partial"
        else "none"
        end
      end

      def find_order
        Ec::Order.where(platform: platform, store_id: store.id)
          .where(
            "external_order_number IN (:numbers) OR external_order_id = :external_id",
            numbers: [ raw_record.posting_number, raw_record.order_number ].compact,
            external_id: raw_record.order_id&.to_s
          ).first
      end

      def find_sku_product
        Ec::SkuProduct.find_by(
          store_id: store.id,
          platform: platform,
          platform_sku_id: raw_record.ozon_sku&.to_s
        )
      end

      def platform_sku_id
        raw_record.ozon_sku&.to_s
      end

      def product_id
        sku_product&.product_id
      end

      def offer_id
        raw_record.offer_id
      end

      def order_item_platform_sku_id
        platform_sku_id
      end

      def quantity
        raw_record.quantity.to_i.positive? ? raw_record.quantity.to_i : 1
      end

      def item_attributes
        super.tap do |attributes|
          attributes[:restockable] = true if source_status == "ReturnedToOzon"
        end
      end

      def item_metadata
        { product_name: raw_record.product_name }
      end
    end
  end
end
