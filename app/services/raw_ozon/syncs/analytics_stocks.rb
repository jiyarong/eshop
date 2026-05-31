module RawOzon
  module Syncs
    module AnalyticsStocks
      # POST /v2/analytics/stock_on_warehouses (offset pagination)
      def sync_analytics_stocks
        offset    = 0
        total     = 0
        synced_at = Time.current
        limit     = 1000

        RawOzon::AnalyticsStock.where(account_id: @account.id).delete_all

        loop do
          resp = @client.post('/v2/analytics/stock_on_warehouses', {
            limit:          limit,
            offset:         offset,
            warehouse_type: 'ALL',
          })
          rows_data = Array(resp.dig('result', 'rows'))
          break if rows_data.empty?

          rows = rows_data.map do |r|
            {
              account_id:    @account.id,
              ozon_sku:      r['sku'],
              item_code:     r['item_code'],
              item_name:     r['item_name'],
              warehouse_name: r['warehouse_name'],
              present:       r['free_to_sell_amount'].to_i,
              reserved:      r['promised_amount'].to_i + r['reserved_amount'].to_i,
              raw_json:      r,
              synced_at:     synced_at,
            }
          end

          RawOzon::AnalyticsStock.insert_all(rows) if rows.any?
          total  += rows.size
          offset += limit
          break if rows_data.size < limit
          sleep 0.5
        end

        total
      end
    end
  end
end
