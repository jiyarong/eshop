module ErpAI
  module V3
    class OperationActionsFullPeriodContext < ErpAI::V2::OperationActionsFullPeriodContext
      EXCLUDED_OPERATION_TYPES = %w[sku_inbound_change].freeze

      def call
        sku.operation_actions
          .includes(:operated_by_user, :sku_product, :store)
          .where(operated_at: user_time_range)
          .where.not(operation_type: EXCLUDED_OPERATION_TYPES)
          .order(:operated_at, :id)
          .map { |action| row_for(action) }
      end

      private

      def row_for(action)
        super.merge(
          operation_type_label: I18n.t("erp.operation_actions.operation_types.#{action.operation_type}"),
          diff_summary: Ec::OperationActionDiffFormatter.summary(action.diff_result, operation_type: action.operation_type)
        )
      end
    end
  end
end
