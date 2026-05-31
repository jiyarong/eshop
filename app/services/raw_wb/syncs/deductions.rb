module RawWb
  module Syncs
    module Deductions
      # GET /api/analytics/v1/deductions — statistics-api (wrong-item substitution fines)
      def sync_deductions
        data  = @client.get(:statistics, '/api/analytics/v1/deductions',
                            dateFrom: @from.iso8601, dateTo: Date.current.iso8601)
        items = Array(data.is_a?(Hash) ? data['data'] || data : data)
        log "  Deductions: #{items.size}"
        items.size
      end
    end
  end
end
