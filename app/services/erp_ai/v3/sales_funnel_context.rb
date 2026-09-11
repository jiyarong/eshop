module ErpAI
  module V3
    class SalesFunnelContext
      def initialize(
        sku:,
        period_from:,
        period_to:,
        time_zone:,
        query: SalesFunnelReports::SkuFunnelAnalysisQuery
      )
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @time_zone = time_zone
        @query = query
      end

      def call
        report = query.run(
          sku: sku,
          from_date: period_from,
          to_date: period_to,
          time_zone: time_zone
        )

        {
          sku_funnel_overview_per_week: {
            metrics: overview_metrics(report),
            periods: overview_periods(report)
          },
          sku_funnel_store_listing_perweek: {
            metrics: report.fetch(:store_metrics),
            periods: periods(report),
            store_listings: store_listings(report)
          }
        }
      end

      private

      attr_reader :sku, :period_from, :period_to, :time_zone, :query

      def overview_metrics(report)
        report.fetch(:common_metrics).reject { |metric| metric == :store_ending_inventory }
      end

      def overview_periods(report)
        metrics = overview_metrics(report)
        report.fetch(:periods).map do |period|
          row = period.fetch(:sku_row)
          period_payload(period).merge(
            values: values_for(row, metrics),
            available_metrics: row.fetch(:available_metrics, []) & metrics
          )
        end
      end

      def periods(report)
        report.fetch(:periods).map { |period| period_payload(period) }
      end

      def store_listings(report)
        metrics = report.fetch(:store_metrics)
        report.fetch(:store_groups).map do |group|
          {
            store_id: group.fetch(:store_id),
            store_ref: group.fetch(:store_ref),
            sku_product_id: group.fetch(:sku_product_id),
            platform: group.fetch(:platform),
            store_name: group.fetch(:store_name),
            listing_label: group.fetch(:listing_label),
            rows_per_week: report.fetch(:periods).map do |period|
              row = group.fetch(:rows_by_period).fetch(period.fetch(:key))
              period_payload(period).merge(
                values: values_for(row, metrics),
                available_metrics: row.fetch(:available_metrics, []) & metrics
              )
            end
          }
        end
      end

      def period_payload(period)
        {
          period_key: period.fetch(:key),
          period_from: period.fetch(:from_date).iso8601,
          period_to: period.fetch(:to_date).iso8601
        }
      end

      def values_for(row, metrics)
        metrics.index_with { |metric| row[metric] }
      end
    end
  end
end
