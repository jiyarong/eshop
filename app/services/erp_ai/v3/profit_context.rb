module ErpAI
  module V3
    class ProfitContext
      OVERVIEW_METRICS = %i[
        net_sales revenue average_price commission_fee payment_fee delivery_fee return_delivery_fee
        storage_fee dispatch_fee packing_fee defect_fee crossdock_fee other_platform_fee ads
        ad_ratio_pct goods_cost cost_ratio_pct pre_tax tax after_tax profit_margin_pct
        average_profit_per_order annualized_return_pct annualized_net_profit_cny
      ].freeze

      STORE_LISTING_METRICS = OVERVIEW_METRICS.dup.freeze

      def initialize(
        sku:,
        period_from:,
        period_to:,
        query: Ec::SkuProfitAnalysisQuery
      )
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @query = query
      end

      def call
        report = query.run(
          sku: sku,
          from_date: period_from,
          to_date: period_to
        )

        {
          sku_profit_overview_per_week: {
            metrics: OVERVIEW_METRICS,
            periods: overview_periods(report)
          },
          sku_profit_store_listing_perweek: {
            metrics: STORE_LISTING_METRICS,
            periods: periods(report),
            store_listings: store_listings(report)
          }
        }
      end

      private

      attr_reader :sku, :period_from, :period_to, :query

      def overview_periods(report)
        report.fetch(:periods).map do |period|
          row = period.fetch(:sku_row)
          period_payload(period).merge(
            values: values_for(row, OVERVIEW_METRICS)
          )
        end
      end

      def periods(report)
        report.fetch(:periods).map { |period| period_payload(period) }
      end

      def store_listings(report)
        report.fetch(:store_groups).map do |group|
          {
            store_ref: group.fetch(:store_ref),
            store_id: store_id_for(group),
            sku_product_id: group[:sku_product_id],
            platform: group[:platform],
            store_name: group[:shop],
            listing_label: group[:listing_label],
            rows_per_week: report.fetch(:periods).map do |period|
              row = group.fetch(:rows_by_period).fetch(period.fetch(:key), {})
              period_payload(period).merge(
                values: values_for(row, STORE_LISTING_METRICS)
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

      def store_id_for(group)
        group[:store_id] || group.dig(:rows_by_period, "P0", :store_id)
      end
    end
  end
end
