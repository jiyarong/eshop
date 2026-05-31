module RawWb
  module Syncs
    module MeasurementPenalties
      # GET /api/analytics/v1/measurement-penalties — statistics-api (package size mismatch fines)
      def sync_measurement_penalties
        data  = @client.get(:statistics, '/api/analytics/v1/measurement-penalties',
                            dateFrom: @from.iso8601, dateTo: Date.current.iso8601)
        items = Array(data.is_a?(Hash) ? data['data'] || data : data)
        log "  Measurement penalties: #{items.size}"
        items.size
      end
    end
  end
end
