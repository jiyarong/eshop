module RawWb
  module Syncs
    module SearchTerms
      # POST /api/v2/search-report/product/search-texts — seller-analytics-api
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
                update_only: %i[
                  orders avg_position median_position frequency week_frequency
                  open_card open_card_percentile
                  add_to_cart add_to_cart_percentile
                  open_to_cart open_to_cart_percentile
                  orders_percentile
                  cart_to_order cart_to_order_percentile
                  visibility
                  vendor_code subject_name brand_name product_name
                  rating feedback_rating price_min price_max
                ])
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
          account_id:               @account.id,
          stat_date:                @from,
          keyword:                  r['text'],
          nm_id:                    r['nmId'],
          orders:                   r.dig('orders', 'current').to_i,
          orders_percentile:        r.dig('orders', 'percentile').to_i,
          avg_position:             r.dig('avgPosition', 'current').to_f,
          median_position:          r.dig('medianPosition', 'current').to_f,
          frequency:                r.dig('frequency', 'current').to_i,
          week_frequency:           r['weekFrequency'].to_i,
          open_card:                r.dig('openCard', 'current').to_i,
          open_card_percentile:     r.dig('openCard', 'percentile').to_i,
          add_to_cart:              r.dig('addToCart', 'current').to_i,
          add_to_cart_percentile:   r.dig('addToCart', 'percentile').to_i,
          open_to_cart:             r.dig('openToCart', 'current').to_f,
          open_to_cart_percentile:  r.dig('openToCart', 'percentile').to_i,
          cart_to_order:            r.dig('cartToOrder', 'current').to_f,
          cart_to_order_percentile: r.dig('cartToOrder', 'percentile').to_i,
          visibility:               r.dig('visibility', 'current').to_i,
          vendor_code:              r['vendorCode'],
          subject_name:             r['subjectName'],
          brand_name:               r['brandName'],
          product_name:             r['name'],
          rating:                   r['rating'].to_f,
          feedback_rating:          r['feedbackRating'].to_f,
          price_min:                r.dig('price', 'minPrice').to_f,
          price_max:                r.dig('price', 'maxPrice').to_f,
        }
      end
    end
  end
end
