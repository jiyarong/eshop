module ErpAI
  module V2
    class OperationActionsFullPeriodContext
      def initialize(sku:, period_from:, period_to:, time_zone:)
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @time_zone = time_zone
      end

      def call
        sku.operation_actions
          .includes(:operated_by_user, :sku_product, :store)
          .where(operated_at: user_time_range)
          .order(:operated_at, :id)
          .map { |action| row_for(action) }
      end

      private

      attr_reader :sku, :period_from, :period_to, :time_zone

      def user_time_range
        time_zone.local(period_from.year, period_from.month, period_from.day).beginning_of_day..
          time_zone.local(period_to.year, period_to.month, period_to.day).end_of_day
      end

      def row_for(action)
        product = action.sku_product
        operator = action.operated_by_user

        {
          action_id: action.id,
          operated_at: action.operated_at,
          operation_type: action.operation_type,
          record_by_system: action.record_by_system,
          platform: action.store.platform,
          store_id: action.store.id,
          store_name: action.store.store_name,
          sku_code: sku.sku_code,
          sku_product_id: product.id,
          platform_product_id: product.product_id,
          platform_sku_id: product.platform_sku_id,
          offer_id: product.offer_id,
          operated_by_user_id: operator.id,
          operated_by_user_name: operator.display_name,
          diff_result: ErpAI::V2::ContextPayloadSanitizer.call(action.diff_result)
        }
      end
    end
  end
end
