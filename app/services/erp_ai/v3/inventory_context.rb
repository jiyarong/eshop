module ErpAI
  module V3
    class InventoryContext
      CURRENT_INVENTORY_FIELDS = %i[
        incoming_quantity
        book_stock
        platform_stock
        fbs_total_stock
        daily_sales_velocity
        turnover_days
        turnover_days_with_procurement
        platform_fbs_stock
        platform_reported_fbs_stock
        strict_forecast_daily_sales
        strict_forecast_cover_days
      ].freeze
      HISTORY_TREND_FIELDS = Ec::SkuInventoryTrendQuery::METRICS
      STORE_TREND_FIELDS = %i[
        platform_stock
        fbs_stock
        platform_inbound_stock
      ].freeze

      def initialize(
        sku:,
        today:,
        time_zone:,
        detail_query: Ec::InventoryPageDetailQuery,
        trend_query: Ec::SkuInventoryTrendQuery
      )
        @sku = sku
        @today = today.to_date
        @time_zone = time_zone
        @detail_query = detail_query
        @trend_query = trend_query
      end

      def call
        detail = detail_query.new(
          sku,
          detail_tab: "overview",
          book_batch_page: nil,
          return_page: nil,
          return_restockable: nil,
          date_to: today,
          time_zone: time_zone
        ).call

        {
          current_inventory_info: {
            fields: CURRENT_INVENTORY_FIELDS,
            values: current_values(detail),
            forecast_explanation: detail[:forecast_explanation],
            strict_forecast: detail[:strict_forecast],
            data_through: latest_inventory_synced_at(detail)
          },
          history_inventory_info: history_inventory_info
        }
      end

      private

      attr_reader :sku, :today, :time_zone, :detail_query, :trend_query

      def history_inventory_info
        trend = trend_query.new(
          sku,
          to_date: today,
          time_zone: time_zone
        ).call

        {
          sku_inventory_trend: {
            metrics: HISTORY_TREND_FIELDS,
            available_metrics: trend.fetch(:available_metrics),
            weeks: trend.fetch(:weeks).map { |row| weekly_trend_row(row) }
          },
          store_listing_inventory_trend: {
            metrics: STORE_TREND_FIELDS,
            from_date: trend.fetch(:store_from_date).iso8601,
            to_date: trend.fetch(:store_to_date).iso8601,
            selected_store_key: trend[:selected_store_key],
            store_options: trend.fetch(:store_options),
            store_listings: trend.fetch(:store_trends).map { |group| store_trend_group(group) }
          }
        }
      end

      def weekly_trend_row(row)
        {
          week_start: row.fetch(:week_start).iso8601,
          week_end: row.fetch(:week_end).iso8601,
          snapshot_date: row[:snapshot_date]&.iso8601,
          is_week_end: row[:is_week_end],
          missing: row.fetch(:missing),
          values: values_for(row.fetch(:metrics, {}), HISTORY_TREND_FIELDS)
        }
      end

      def store_trend_group(group)
        {
          store_key: group.fetch(:key),
          store_label: group.fetch(:label),
          days: group.fetch(:days).map do |row|
            {
              date: row.fetch(:date).iso8601,
              snapshot_date: row[:snapshot_date]&.iso8601,
              missing: row.fetch(:missing),
              values: values_for(row.fetch(:metrics, {}), STORE_TREND_FIELDS)
            }
          end
        }
      end

      def current_values(detail)
        strict = detail[:strict_forecast] || {}
        summary = detail[:summary] || {}
        values = {
          incoming_quantity: detail[:incoming_quantity],
          book_stock: summary[:book_stock],
          platform_stock: summary[:fbo_fbw_stock],
          fbs_total_stock: summary[:available_stock],
          daily_sales_velocity: detail[:daily_sales_velocity],
          turnover_days: detail[:turnover_days],
          turnover_days_with_procurement: detail[:turnover_days_with_procurement],
          platform_fbs_stock: detail[:fbs_stock],
          platform_reported_fbs_stock: platform_reported_fbs_stock(detail),
          strict_forecast_daily_sales: strict.dig(:calculation, :path).to_s == "no_valid_days" ? nil : strict[:forecast_daily_sales],
          strict_forecast_cover_days: strict[:cover_days]
        }

        CURRENT_INVENTORY_FIELDS.index_with { |field| values[field] }
      end

      def platform_reported_fbs_stock(detail)
        source_levels = latest_fbs_levels
        source_levels = fbs_levels(detail) if source_levels.empty?

        source_levels.sum do |level|
          metadata_value(level, :raw_fbs_quantity) || level_quantity(level)
        end
      end

      def latest_inventory_synced_at(detail)
        Array(detail[:platform_breakdown]).filter_map { |row| row[:latest_synced_at] }.max
      end

      def fbs_levels(detail)
        Array(detail[:platform_breakdown])
          .filter_map { |row| row.is_a?(Hash) ? row.with_indifferent_access : nil }
          .select { |row| row[:fulfillment_type].to_s == "fbs" }
      end

      def metadata_value(level, key)
        metadata = level.respond_to?(:metadata) ? level.metadata : level[:metadata]
        return unless metadata.is_a?(Hash)

        value = metadata[key] || metadata[key.to_s]
        Integer(value, exception: false)
      end

      def level_quantity(level)
        value = level.respond_to?(:quantity) ? level.quantity : level[:quantity]
        value.to_i
      end

      def latest_fbs_levels
        @latest_fbs_levels ||= sku.inventory_levels.latest.where(fulfillment_type: "fbs").to_a
      end

      def values_for(row, fields)
        fields.index_with { |field| row[field] }
      end
    end
  end
end
