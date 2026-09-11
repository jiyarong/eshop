module ErpAI
  module V3
    class WarehouseRecommendationContext
      def initialize(sku:, period_from:, period_to:, time_zone:, target_days: nil)
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @time_zone = time_zone
        @target_days = target_days
      end

      def call
        {
          sales_period: {
            from: period_from.iso8601,
            to: period_to.iso8601,
            days: period_days,
            source: "ec_orders.ordered_at"
          },
          target_days: bounded_target_days,
          stores: stores.map { |store| store_context(store) }
        }
      end

      private

      attr_reader :sku, :period_from, :period_to, :time_zone, :target_days

      def stores
        @stores ||= sku.sku_products.includes(:store).map(&:store).uniq(&:id)
          .select { |store| store.is_active? && store.platform.in?(%w[ozon wb]) && account_id_for(store).present? }
          .sort_by { |store| [store.platform.to_s, store.store_name.to_s, store.id] }
      end

      def store_context(store)
        report = query_class_for(store).new(
          store: store,
          from_date: period_from,
          to_date: period_to,
          time_zone: time_zone,
          target_days: bounded_target_days,
          sku_codes: [sku.sku_code]
        ).call
        row = Array(report[:rows]).find { |item| item[:sku_code] == sku.sku_code }

        source_payload(store).merge(
          data_status: row ? "available" : "no_records",
          inventory_synced_at: report[:inventory_synced_at],
          summary: summary_payload(report, row),
          sales_clusters: Array(row&.fetch(:clusters, [])).map { |cluster| cluster_payload(cluster, row) }
        )
      rescue ActiveRecord::RecordNotFound, ArgumentError, KeyError, TypeError
        source_payload(store).merge(
          data_status: "unavailable",
          inventory_synced_at: nil,
          summary: nil,
          sales_clusters: [],
          reason: "source_unavailable"
        )
      end

      def source_payload(store)
        {
          store_ref: "#{store.platform}:#{account_id_for(store)}",
          platform: store.platform,
          store_id: store.id,
          store_name: store.store_name
        }
      end

      def summary_payload(report, row)
        summary = report.fetch(:summary, {})
        return empty_summary(summary) unless row

        {
          status: row[:status],
          sales_quantity: row[:sales_quantity],
          daily_sales: row[:daily_sales],
          days_of_stock: row[:days_of_stock],
          available: row[:available],
          reserved: row[:reserved],
          inbound: row[:inbound],
          fbs_available: row[:fbs_available],
          recommended: row[:recommended],
          distribution_gap: row[:distribution_gap],
          mapped_orders: summary[:mapped_orders],
          total_orders: summary[:total_orders],
          mapping_coverage: summary[:mapping_coverage]
        }
      end

      def empty_summary(summary)
        {
          status: nil,
          sales_quantity: 0,
          daily_sales: 0,
          days_of_stock: nil,
          available: summary[:available].to_i,
          reserved: 0,
          inbound: summary[:inbound].to_i,
          fbs_available: 0,
          recommended: summary[:recommended].to_i,
          distribution_gap: 0,
          mapped_orders: summary[:mapped_orders],
          total_orders: summary[:total_orders],
          mapping_coverage: summary[:mapping_coverage]
        }
      end

      def cluster_payload(cluster, row)
        sales_quantity = cluster[:sales_quantity].to_i

        {
          cluster_name: cluster[:cluster_name],
          status: cluster[:status],
          sales_quantity: sales_quantity,
          sales_share_pct: percentage(sales_quantity, row[:sales_quantity].to_i),
          daily_sales: cluster[:daily_sales],
          days_of_stock: cluster[:days_of_stock],
          available: cluster[:available],
          reserved: cluster[:reserved],
          inbound: cluster[:inbound],
          distribution_gap: cluster[:distribution_gap],
          receiving_warehouse_count: cluster[:receiving_warehouse_count],
          warehouses: Array(cluster[:warehouses]).map { |warehouse| warehouse_payload(warehouse) }
        }
      end

      def warehouse_payload(warehouse)
        {
          warehouse_name: warehouse[:warehouse_name],
          warehouse_id: warehouse[:warehouse_id],
          cluster_name: warehouse[:cluster_name],
          available: warehouse[:available],
          reserved: warehouse[:reserved],
          inbound: warehouse[:inbound]
        }
      end

      def query_class_for(store)
        store.platform == "wb" ? Ec::WbWarehouseRecommendationQuery : Ec::OzonWarehouseRecommendationQuery
      end

      def account_id_for(store)
        store.platform == "wb" ? store.wb_raw_account_id : store.ozon_raw_account_id
      end

      def bounded_target_days
        @bounded_target_days ||= begin
          days = target_days.to_i
          days = Ec::OzonWarehouseRecommendationQuery::DEFAULT_TARGET_DAYS unless days.positive?
          [days, Ec::OzonWarehouseRecommendationQuery::MAX_TARGET_DAYS].min
        end
      end

      def percentage(numerator, denominator)
        return nil unless denominator.positive?

        (numerator.to_d / denominator * 100).round(2)
      end

      def period_days
        (period_to - period_from).to_i + 1
      end
    end
  end
end
