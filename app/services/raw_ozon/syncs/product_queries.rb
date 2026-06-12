module RawOzon
  module Syncs
    module ProductQueries
      # POST /v1/analytics/product-queries        — SKU 级搜索汇总
      # POST /v1/analytics/product-queries/details — 词级搜索明细（每 SKU 最多 15 词）
      def sync_product_queries
        skus = RawOzon::Product.where(account_id: @account.id)
                               .filter_map { |p| p.raw_json&.dig('sku')&.to_s }
                               .uniq
        return 0 if skus.empty?

        synced_at  = Time.current
        total      = 0
        page_size  = 1000

        skus.each_slice(200) do |slice|
          # ── 1. SKU 级汇总 ──────────────────────────────────────────────────
          page = 0
          loop do
            resp = @client.post('/v1/analytics/product-queries', {
              date_from: @from.to_date.to_time.utc.iso8601,
              date_to:   Date.current.to_time.utc.iso8601,
              skus:      slice,
              page:      page,
              page_size: page_size,
              sort_by:   'BY_SEARCHES',
              sort_dir:  'DESCENDING',
            })
            items      = Array(resp['items'])
            period     = resp['analytics_period'] || {}
            period_from = Date.parse(period['date_from']) rescue @from.to_date
            period_to   = Date.parse(period['date_to'])   rescue Date.current

            rows = items.map do |item|
              {
                account_id:          @account.id,
                period_from:         period_from,
                period_to:           period_to,
                sku:                 item['sku'].to_i,
                offer_id:            item['offer_id'],
                name:                item['name'],
                category:            item['category'],
                currency:            item['currency'],
                unique_search_users: item['unique_search_users'].to_i,
                unique_view_users:   item['unique_view_users'].to_i,
                position:            item['position'].to_f,
                view_conversion:     item['view_conversion'].to_f,
                gmv:                 item['gmv'].to_f,
                synced_at:           synced_at,
              }
            end

            RawOzon::ProductQuery.upsert_all(rows,
              unique_by: :idx_ozon_product_queries_unique,
              update_only: %i[period_to offer_id name category currency
                              unique_search_users unique_view_users
                              position view_conversion gmv synced_at]
            ) if rows.any?

            total += rows.size
            break if items.size < page_size
            page += 1
          end

          # ── 2. 词级明细 ────────────────────────────────────────────────────
          page = 0
          loop do
            resp = @client.post('/v1/analytics/product-queries/details', {
              date_from:    @from.to_date.to_time.utc.iso8601,
              date_to:      Date.current.to_time.utc.iso8601,
              skus:         slice,
              limit_by_sku: 15,
              page:         page,
              page_size:    page_size,
              sort_by:      'BY_SEARCHES',
              sort_dir:     'DESCENDING',
            })
            queries    = Array(resp['queries'])
            period     = resp['analytics_period'] || {}
            period_from = Date.parse(period['date_from']) rescue @from.to_date
            period_to   = Date.parse(period['date_to'])   rescue Date.current

            rows = queries.map do |q|
              {
                account_id:          @account.id,
                period_from:         period_from,
                period_to:           period_to,
                sku:                 q['sku'].to_i,
                query:               q['query'].to_s,
                query_index:         q['query_index'].to_i,
                currency:            q['currency'],
                unique_search_users: q['unique_search_users'].to_i,
                unique_view_users:   q['unique_view_users'].to_i,
                position:            q['position'].to_f,
                view_conversion:     q['view_conversion'].to_f,
                order_count:         q['order_count'].to_i,
                gmv:                 q['gmv'].to_f,
                synced_at:           synced_at,
              }
            end

            RawOzon::ProductQueryDetail.upsert_all(rows,
              unique_by: :idx_ozon_product_query_details_unique,
              update_only: %i[period_to query_index currency
                              unique_search_users unique_view_users
                              position view_conversion order_count gmv synced_at]
            ) if rows.any?

            break if queries.size < page_size
            page += 1
          end

          sleep 1
        end

        total
      end
    end
  end
end
