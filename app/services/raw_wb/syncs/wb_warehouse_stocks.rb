module RawWb
  module Syncs
    module WbWarehouseStocks
      # POST /api/analytics/v1/stocks-report/wb-warehouses — seller-analytics-api
      # Returns real-time stock levels across WB's own warehouses (read-only snapshot)
      def sync_wb_warehouse_stocks
        data  = @client.post(:seller_analytics, '/api/analytics/v1/stocks-report/wb-warehouses', {})
        items = Array(data.dig('data', 'items') || data['data'] || data)
        log "  WB warehouse stocks snapshot: #{items.size} items"
        items.size
      end
    end
  end
end
