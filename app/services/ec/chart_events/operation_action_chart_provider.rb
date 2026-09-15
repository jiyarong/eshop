module Ec
  module ChartEvents
    class OperationActionChartProvider
      def self.call(sku:, from_time:, to_time:, user_time_zone:, level:, store: nil, sku_product: nil)
        return [] unless %i[sku listing].include?(level.to_sym)

        OperationActionChartEventsQuery.run(
          sku:, from_time:, to_time:, user_time_zone:,
          store: level.to_sym == :listing ? store : nil,
          sku_product:
        ).map do |event|
          event.merge(
            key: "operation_action:#{event.fetch(:id)}",
            source_type: "operation_action",
            event_type: event[:operation_type],
            occurred_at: event[:operated_at],
            sku_id: sku.id,
            chart_levels: %w[sku listing],
            title: event[:operation_type_label],
            context_label: event[:store_name],
            summary: event[:diff_summary],
            details: event[:diff_result]
          )
        end
      end
    end
  end
end
