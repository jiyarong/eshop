module Ec
  class InboundInventoryChangeRecorder
    class << self
      def record(previous_level:, current_level:)
        return unless previous_level && current_level
        return if previous_level.quantity == current_level.quantity

        sku_product = sku_product_for(current_level)
        return unless sku_product

        delta = current_level.quantity - previous_level.quantity
        Ec::ListingChangeRecorder.record(
          sku_product:,
          operation_type: "sku_inbound_change",
          before: { platform_inbound_quantity: previous_level.quantity },
          after: { platform_inbound_quantity: current_level.quantity },
          operated_at: current_level.synced_at,
          metadata: {
            inbound_change: {
              account_id: current_level.account_id,
              delta: delta,
              direction: delta.positive? ? "increased" : "decreased",
              inferred_event: delta.positive? ? "shipment_started" : "shipment_arrived"
            }
          }
        )
      end

      private

      def sku_product_for(level)
        scope = Ec::SkuProduct.includes(:sku, :store).where(
          sku_code: level.sku_code,
          platform: level.platform
        )
        scope = scope.where(store_id: level.store_id) if level.store_id.present?
        scope.order(:id).first
      end
    end
  end
end
