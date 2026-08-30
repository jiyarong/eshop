module ErpAI
  module V2
    class SearchTermsContext
      def initialize(
        sku:,
        period_from:,
        period_to:,
        today: Date.current,
        store_ids: nil,
        partial_on_today: false
      )
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @today = today.to_date
        @store_ids = store_ids&.map(&:to_i)&.uniq
        @partial_on_today = partial_on_today
      end

      def call
        weekly_periods.map do |period|
          {
            period_from: period.fetch(:period_from).iso8601,
            period_to: period.fetch(:period_to).iso8601,
            is_partial: period_partial?(period),
            stores: stores.map { |store| store_payload(store, period) }
          }
        end
      end

      private

      attr_reader :sku, :period_from, :period_to, :today, :store_ids, :partial_on_today

      def weekly_periods
        (period_from..period_to).step(7).map do |week_start|
          { period_from: week_start, period_to: week_start.end_of_week(:monday) }
        end
      end

      def period_partial?(period)
        period.fetch(:period_to) > today || (partial_on_today && period.fetch(:period_to) == today)
      end

      def stores
        scope = sku.sku_products.includes(:store)
        scope = scope.where(store_id: store_ids) unless store_ids.nil?

        @stores ||= scope.map(&:store).uniq
          .select { |store| %w[wb ozon].include?(store.platform) && account_id_for(store).present? }
          .sort_by { |store| [ store.platform, store.id ] }
      end

      def store_payload(store, period)
        rows = SearchTermReports::Query.new(
          platform: store.platform,
          store: store,
          period_from: period.fetch(:period_from),
          period_to: period.fetch(:period_to),
          sku_codes: [ sku.sku_code ]
        ).rows.map { |row| row.except(:sku) }

        {
          store_ref: "#{store.platform}:#{account_id_for(store)}",
          platform: store.platform,
          store_id: store.id,
          store_name: store.store_name,
          data_status: rows.any? ? "available" : "no_records",
          data: rows
        }
      rescue ActiveRecord::RecordNotFound, ArgumentError, KeyError, TypeError
        {
          store_ref: "#{store.platform}:#{account_id_for(store)}",
          platform: store.platform,
          store_id: store.id,
          store_name: store.store_name,
          data_status: "unavailable",
          reason: "source_unavailable",
          data: []
        }
      end

      def account_id_for(store)
        store.platform == "wb" ? store.wb_raw_account_id : store.ozon_raw_account_id
      end
    end
  end
end
