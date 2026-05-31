module RawWb
  module Syncs
    module SearchTerms
      # POST /api/v2/search-report/product/search-texts — seller-analytics-api
      # topOrderBy must be a string (not an object). Requires nmIds at top level.
      def sync_search_terms
        nm_ids = RawWb::Product.where(account_id: @account.id).pluck(:nm_id).compact.uniq
        return 0 if nm_ids.empty?

        total = 0
        nm_ids.each_slice(10) do |slice|
          offset = 0
          limit  = 100
          loop do
            body = {
              nmIds:         slice,
              currentPeriod: { start: @from.iso8601, end: Date.current.iso8601 },
              topOrderBy:    'orders',
              orderBy:       { field: 'orders', mode: 'desc' },
              limit:         limit,
              offset:        offset,
            }
            data  = @client.post(:seller_analytics, '/api/v2/search-report/product/search-texts', body)
            items = Array(data.dig('data', 'items'))
            break if items.empty?

            rows = items.filter_map { |r| build_search_term(r) }
            if rows.any?
              RawWb::AnalyticsSearchTerm.upsert_all(rows,
                unique_by: :idx_raw_wb_search_terms_unique,
                update_only: %i[orders avg_position frequency])
              total += rows.size
            end

            break if items.size < limit
            offset += limit
            sleep 0.5
          end
          sleep 1
        end

        total
      end

      private

      def build_search_term(r)
        return nil if r['text'].blank?
        {
          account_id:   @account.id,
          stat_date:    @from,
          keyword:      r['text'],
          nm_id:        r['nmId'],
          orders:       r.dig('orders', 'current').to_i,
          avg_position: r.dig('avgPosition', 'current').to_f,
          frequency:    r.dig('frequency', 'current').to_i,
        }
      end
    end
  end
end
