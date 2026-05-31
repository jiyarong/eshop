module RawWb
  module Syncs
    module BannedProducts
      # GET /api/v1/analytics/banned-products/blocked — statistics-api
      def sync_banned_products
        data   = @client.get(:statistics, '/api/v1/analytics/banned-products/blocked')
        items  = Array(data.is_a?(Hash) ? data['data'] || data : data)
        return 0 if items.empty?

        nm_ids = items.filter_map { |r| r['nmId'] || r['nmID'] }.uniq
        RawWb::Product.where(nm_id: nm_ids).update_all(is_in_trash: true) if nm_ids.any?
        log "  Blocked products: #{nm_ids.size}"
        nm_ids.size
      end
    end
  end
end
