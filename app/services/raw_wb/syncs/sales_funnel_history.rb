module RawWb
  module Syncs
    module SalesFunnelHistory
      # POST /api/analytics/v3/sales-funnel/products/history — seller-analytics-api (per-day breakdown)
      # Requires nmIds at top level (not inside filter).
      # Response: direct array of { product, history: [{ date, openCount, ... }] }
      def sync_sales_funnel_history
        nm_ids = RawWb::AnalyticsSalesFunnel.where(account_id: @account.id).distinct.pluck(:nm_id)
        return 0 if nm_ids.empty?

        # API max lookback is 7 days regardless of @from
        effective_from = [@from.to_date, 7.days.ago.to_date].max
        total = 0
        today  = Date.current
        chunks = []
        cursor = effective_from
        while cursor <= today
          chunks << [cursor, [cursor + 6, today].min]
          cursor = cursor + 7
        end
        chunks.each do |chunk_from, chunk_to|
          nm_ids.each_slice(20) do |slice|
            body = {
              nmIds:          slice,
              selectedPeriod: { start: chunk_from.iso8601, end: chunk_to.iso8601 },
              page:           1,
              period:         'day',
            }

            data  = @client.post(:seller_analytics, '/api/analytics/v3/sales-funnel/products/history', body)
            items = Array(data)
            rows  = items.flat_map { |p| build_funnel_history_rows(p) }.compact
            next if rows.empty?

            RawWb::AnalyticsSalesFunnel.upsert_all(rows,
              unique_by: %i[account_id stat_date nm_id],
              update_only: %i[open_card add_to_cart orders orders_sum buyouts buyouts_sum
                              cancel_count cancel_sum conv_to_cart cart_to_order buyout_percent
                              avg_price avg_orders_per_day])
            total += rows.size
            sleep 1
          end
        end

        total
      end

      private

      def build_funnel_history_rows(p)
        prod  = p['product'] || {}
        nm_id = prod['nmId'] || prod['nmID']
        return [] if nm_id.blank?

        Array(p['history']).filter_map do |h|
          stat_date = h['date']
          next if stat_date.blank?
          {
            account_id:         @account.id,
            stat_date:          stat_date,
            nm_id:              nm_id,
            vendor_code:        prod['vendorCode'],
            brand:              prod['brandName'],
            open_card:          h['openCount'].to_i,
            add_to_cart:        h['cartCount'].to_i,
            orders:             h['orderCount'].to_i,
            orders_sum:         h['orderSum'].to_f,
            buyouts:            h['buyoutCount'].to_i,
            buyouts_sum:        h['buyoutSum'].to_f,
            cancel_count:       0,
            cancel_sum:         0,
            conv_to_cart:       h['addToCartConversion'].to_f,
            cart_to_order:      h['cartToOrderConversion'].to_f,
            buyout_percent:     h['buyoutPercent'].to_f,
            avg_price:          0,
            avg_orders_per_day: 0,
          }
        end
      end
    end
  end
end
