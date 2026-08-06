module Ec
  module Returns
    class BaseNormalizer
      def initialize(raw_record)
        @raw_record = raw_record
      end

      def call
        ApplicationRecord.transaction do
          normalized_return = Ec::Return.find_or_initialize_by(
            platform: platform,
            store: store,
            return_key: return_key
          )
          normalized_return.assign_attributes(return_attributes)
          normalized_return.save!

          item = normalized_return.items.find_or_initialize_by(item_key: item_key)
          item.assign_attributes(item_attributes)
          item.save!

          source_link = Ec::ReturnSourceLink.find_or_initialize_by(
            source_type: raw_record.class.name,
            source_id: raw_record.id
          )
          source_link.assign_attributes(
            return: normalized_return,
            item: item,
            platform: platform,
            source_key: return_key,
            synced_at: raw_record.synced_at
          )
          source_link.save!

          normalized_return
        end
      end

      private

      attr_reader :raw_record

      def store
        @store ||= Ec::Store.find_by!(store_lookup)
      end

      def order
        @order ||= find_order
      end

      def sku_product
        @sku_product ||= find_sku_product
      end

      def order_item
        return unless order && sku_product

        order.items.find_by(
          store_id: store.id,
          platform: platform,
          platform_sku_id: order_item_platform_sku_id
        )
      end

      def item_attributes
        {
          store: store,
          platform: platform,
          sku_product: sku_product,
          order_item: order_item,
          platform_sku_id: platform_sku_id,
          product_id: product_id,
          offer_id: offer_id,
          quantity: quantity,
          metadata: item_metadata
        }
      end

      def item_metadata
        {}
      end
    end
  end
end
