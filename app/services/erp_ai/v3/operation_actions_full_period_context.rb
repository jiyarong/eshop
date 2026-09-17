module ErpAI
  module V3
    class OperationActionsFullPeriodContext < ErpAI::V2::OperationActionsFullPeriodContext
      EXCLUDED_OPERATION_TYPES = %w[sku_inbound_change].freeze
      COMPACT_LISTING_OPERATION_TYPES = %w[listing_content listing_specification].freeze
      ATTRIBUTE_COLLECTION_FIELDS = %w[attributes characteristics variants].freeze
      CHANGE_KEYS = Ec::OperationActionDiffFormatter::CHANGE_KEYS

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
          diff_summary: diff_summary(action)
        )
      end

      def diff_summary(action)
        unless COMPACT_LISTING_OPERATION_TYPES.include?(action.operation_type)
          return Ec::OperationActionDiffFormatter.summary(action.diff_result, operation_type: action.operation_type)
        end

        modified_count, deleted_count = listing_change_counts(action.diff_result)
        [
          I18n.t(
            "erp.operation_actions.diff_summaries.attribute_counts",
            modified_count: modified_count,
            deleted_count: deleted_count
          )
        ]
      end

      def listing_change_counts(diff_result)
        fields = diff_result.to_h.deep_stringify_keys.fetch("fields", {})
        changes = fields.flat_map do |field, change|
          logical_changes(field, change)
        end
        deleted_count = changes.count { |change| deleted_change?(change) }
        [ changes.size - deleted_count, deleted_count ]
      end

      def logical_changes(field, change)
        return [ change ] unless change.is_a?(Hash)
        return [ change ] if change_node?(change)
        return change.values if ATTRIBUTE_COLLECTION_FIELDS.include?(field)

        change.flat_map { |nested_field, nested_change| logical_changes(nested_field, nested_change) }
      end

      def change_node?(change)
        (change.keys.map(&:to_s) & CHANGE_KEYS).any?
      end

      def deleted_change?(change)
        change = change.to_h.deep_stringify_keys
        change.key?("to") && change["to"].nil?
      end
    end
  end
end
