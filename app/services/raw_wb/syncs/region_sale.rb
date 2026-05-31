module RawWb
  module Syncs
    module RegionSale
      # GET /api/v1/analytics/region-sale — seller-analytics-api (not statistics)
      def sync_region_sale
        total = 0
        date_chunks(chunk_days: 31).each do |chunk_from, chunk_to|
          data  = @client.get(:seller_analytics, '/api/v1/analytics/region-sale',
                              dateFrom: chunk_from.iso8601, dateTo: chunk_to.iso8601)
          items = Array(data.is_a?(Hash) ? data['report'] || data['data'] || data : data)
          total += items.size
          sleep 1
        end
        log "  Region sale data: #{total} regions"
        total
      end
    end
  end
end
