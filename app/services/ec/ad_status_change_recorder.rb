module Ec
  class AdStatusChangeRecorder
    class << self
      def record(sku_product:, advertisement_id:, advertisement_name:, before_status:, after_status:, operated_at: Time.current)
        before_enabled = enabled?(sku_product.platform, before_status)
        after_enabled = enabled?(sku_product.platform, after_status)
        return if before_enabled == after_enabled

        Ec::ListingChangeRecorder.record(
          sku_product:,
          operation_type: "sku_adv_on_off",
          before: { advertising_enabled: before_enabled },
          after: { advertising_enabled: after_enabled },
          operated_at:,
          metadata: {
            advertisement: {
              id: advertisement_id.to_s,
              name: advertisement_name,
              status_from: before_status,
              status_to: after_status
            }
          }
        )
      end

      private

      def enabled?(platform, status)
        case platform
        when "wb"
          status.to_i == 9
        when "ozon"
          status == "CAMPAIGN_STATE_RUNNING"
        else
          false
        end
      end
    end
  end
end
