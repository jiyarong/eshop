module ErpAI
  module V2
    class SalesFunnelContext
      def initialize(
        sku:,
        period_from:,
        period_to:,
        store_options: SalesFunnelReports::ReportQueryRunner.store_options,
        query_runner: SalesFunnelReports::SkuDailyReportQueryRunner
      )
        @sku = sku
        @period_from = period_from
        @period_to = period_to
        @store_options = store_options
        @query_runner = query_runner
      end

      def call
        weekly_periods.map do |period|
          period_payload(period).merge(stores: store_payloads(period))
        end
      end

      private

      attr_reader :sku, :period_from, :period_to, :store_options, :query_runner

      def weekly_periods
        (period_from..period_to).step(7).map do |week_start|
          { period_from: week_start, period_to: week_start.end_of_week(:monday) }
        end
      end

      def store_payloads(period)
        store_options.map { |store| store_payload(store, period) }
      end

      def store_payload(store, period)
        report = query_runner.run(
          params: {
            store_ref: store.fetch(:ref),
            from_date: period.fetch(:period_from).iso8601,
            to_date: period.fetch(:period_to).iso8601,
            sku_code: sku.sku_code
          },
          today: period.fetch(:period_to),
          include_comparison: false
        )

        source_payload(store).merge(data: report.fetch(:rows))
      rescue ActiveRecord::RecordNotFound, ArgumentError, KeyError, TypeError
        source_payload(store).merge(
          data_status: "unavailable",
          reason: "source_unavailable",
          data: []
        )
      end

      def source_payload(store)
        {
          store_ref: store.fetch(:ref),
          platform: store.fetch(:platform),
          store_id: source_store_id(store.fetch(:ref)),
          store_name: store.fetch(:name)
        }
      end

      def source_store_id(store_ref)
        value = store_ref.to_s.split(":", 2).last
        store_id = Integer(value, exception: false)
        store_id if store_id&.positive?
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
