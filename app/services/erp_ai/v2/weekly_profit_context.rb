module ErpAI
  module V2
    class WeeklyProfitContext
      def initialize(
        sku:,
        period_from:,
        period_to:,
        store_options: WeeklyProfitReports::ReportQueryRunner.store_options,
        wr_query: Ec::WeeklyProfitReportQuery,
        wsu_query: Ec::WeeklySummaryQuery,
        wsu_deep_query: Ec::WeeklySummaryDeepQuery
      )
        @sku = sku
        @period_from = period_from
        @period_to = period_to
        @store_options = store_options
        @wr_query = wr_query
        @wsu_query = wsu_query
        @wsu_deep_query = wsu_deep_query
      end

      def call
        {
          wr: weekly_periods.map { |period| wr_period(period) },
          wsu: weekly_periods.map { |period| report_period(period, wsu_query) },
          wsu_deep: weekly_periods.map { |period| report_period(period, wsu_deep_query) }
        }
      end

      private

      attr_reader :sku, :period_from, :period_to, :store_options, :wr_query, :wsu_query, :wsu_deep_query

      def weekly_periods
        profit_period_from = period_from - 1.week
        profit_period_to = period_to - 1.week

        @weekly_periods ||= (profit_period_from..profit_period_to).step(7).map do |week_start|
          { period_from: week_start, period_to: week_start.end_of_week(:monday) }
        end
      end

      def report_period(period, query_class)
        report = query_class.run(
          from_date: period.fetch(:period_from),
          to_date: period.fetch(:period_to),
          sku_codes: [sku.sku_code],
          include_comparison: false
        )

        period_payload(period).merge(data: report.fetch(:rows))
      end

      def wr_period(period)
        stores = store_options.map do |store|
          report = wr_query.run(
            store_ref: store.fetch(:ref),
            from_date: period.fetch(:period_from),
            to_date: period.fetch(:period_to),
            sku_codes: [sku.sku_code],
            include_comparison: false
          )

          {
            store_ref: store.fetch(:ref),
            platform: store.fetch(:platform),
            store_id: store.fetch(:ref).split(":", 2).last.to_i,
            store_name: store.fetch(:name),
            data: report.fetch(:rows)
          }
        end

        period_payload(period).merge(stores: stores)
      end

      def period_payload(period)
        {
          period_from: period.fetch(:period_from).iso8601,
          period_to: period.fetch(:period_to).iso8601
        }
      end
    end
  end
end
