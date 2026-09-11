module ErpAI
  module V3
    class LifecycleContext
      SUMMARY_FIELDS = %i[
        first_sale_at
        lifecycle_days
        current_grade
        current_stage
        net_sales
        revenue
        net_profit
        daily_sales_velocity
        inventory_cover_days
        stockout_adjusted_daily_sales
        stockout_adjusted_inventory_cover_days
      ].freeze

      def initialize(
        sku:,
        today:,
        time_zone:,
        query: Ec::SkuLifecycleQuery
      )
        @sku = sku
        @today = today.to_date
        @time_zone = time_zone
        @query = query
      end

      def call
        lifecycle = query.new(
          sku,
          user_today: today,
          time_zone: time_zone
        ).call

        {
          summary: summary_payload(lifecycle.fetch(:summary)),
          key_events: key_events(lifecycle)
        }
      end

      private

      attr_reader :sku, :today, :time_zone, :query

      def summary_payload(summary)
        {
          fields: SUMMARY_FIELDS,
          values: SUMMARY_FIELDS.index_with { |field| summary[field] }
        }
      end

      def key_events(lifecycle)
        {
          sold: lifecycle.fetch(:sold),
          data_started_on: lifecycle[:data_started_on]&.iso8601,
          events: lifecycle.fetch(:events).map { |event| event_payload(event) }
        }
      end

      def event_payload(event)
        record = event.fetch(:record)
        {
          id: event.fetch(:id),
          event_type: event.fetch(:event_type),
          occurred_at: event.fetch(:occurred_at),
          occurred_on: event.fetch(:occurred_at).in_time_zone(time_zone).to_date.iso8601,
          source_type: record.source_type,
          source_id: record.source_id,
          source_key: record.source_key,
          sku_product_id: record.sku_product_id,
          content: event.fetch(:content),
          duration_days: event[:duration_days],
          details: event[:details]
        }
      end
    end
  end
end
