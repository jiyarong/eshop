module ErpAI
  module V2
    class SearchTermsContext
      def initialize(sku:, period_from:, period_to:, today: Date.current)
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @today = today.to_date
      end

      def call
        weekly_periods.map do |period|
          {
            period_from: period.fetch(:period_from).iso8601,
            period_to: period.fetch(:period_to).iso8601,
            is_partial: period.fetch(:period_to) > today,
            stores: stores.map { |store| store_payload(store, period) }
          }
        end
      end

      private

      attr_reader :sku, :period_from, :period_to, :today

      def weekly_periods
        (period_from..period_to).step(7).map do |week_start|
          { period_from: week_start, period_to: week_start.end_of_week(:monday) }
        end
      end

      def stores
        @stores ||= sku.sku_products.includes(:store).map(&:store).uniq
          .select { |store| %w[wb ozon].include?(store.platform) && account_id_for(store).present? }
          .sort_by { |store| [store.platform, store.id] }
      end

      def store_payload(store, period)
        rows = SearchTermReports::Query.new(
          platform: store.platform,
          store: store,
          period_from: period.fetch(:period_from),
          period_to: period.fetch(:period_to),
          sku_codes: [sku.sku_code]
        ).rows.map { |row| row.except(:sku) }

        {
          store_ref: "#{store.platform}:#{account_id_for(store)}",
          platform: store.platform,
          store_id: store.id,
          store_name: store.store_name,
          data_status: rows.any? ? "available" : "no_records",
          data: rows
        }
      end

      def account_id_for(store)
        store.platform == "wb" ? store.wb_raw_account_id : store.ozon_raw_account_id
      end
    end
  end
end
