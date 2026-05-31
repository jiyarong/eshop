module RawWb
  module Syncs
    module GoodsReturn
      # GET /api/v1/analytics/goods-return — seller-analytics-api (not statistics, not POST)
      def sync_goods_return
        total = 0
        date_chunks(chunk_days: 31).each do |chunk_from, chunk_to|
          data  = @client.get(:seller_analytics, '/api/v1/analytics/goods-return',
                              dateFrom: chunk_from.iso8601, dateTo: chunk_to.iso8601)
          items = Array(data.is_a?(Hash) ? data['report'] || data['data'] || data : data)
          total += items.size
          sleep 1
        end
        log "  Goods return: #{total} items"
        total
      end
    end
  end
end
