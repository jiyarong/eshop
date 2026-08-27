module ErpAI
  module V2
    class InventoryContext
      def initialize(sku:, period_from:, period_to:, today:, time_zone:)
        @sku = sku
        @period_from = period_from
        @period_to = period_to
        @today = today
        @time_zone = time_zone
      end

      def call
        {
          current_inventory_info: current_inventory_info,
          history_inventory_info: history_inventory_info
        }
      end

      private

      attr_reader :sku, :period_from, :period_to, :today, :time_zone

      def current_inventory_info
        metrics = Ec::InventoryVelocityMetricsQuery.new(
          sku_codes: [sku.sku_code],
          date_to: today,
          time_zone: time_zone
        ).call.fetch(sku.sku_code, {})
        raw_row = Ec::InventoryPageRowQuery.new(sku).call

        {
          list: Ec::InventoryReportRowMetricsBuilder.call(
            raw_row,
            metrics: metrics,
            cache_updated_at: Time.current
          ),
          detail: Ec::InventoryPageDetailQuery.new(
            sku,
            detail_tab: nil,
            book_batch_page: nil,
            return_page: nil,
            return_restockable: nil,
            date_to: today,
            time_zone: time_zone
          ).call
        }
      end

      def history_inventory_info
        Ec::Snapshot
          .of_type(Ec::InventorySnapshot.snapshot_type)
          .for_sku(sku)
          .between(period_from, period_to)
          .order(:snapshot_date, :id)
          .map do |snapshot|
            {
              snapshot_date: snapshot.snapshot_date.iso8601,
              content: snapshot.data
            }
          end
      end
    end
  end
end
