module RawOzon
  module Syncs
    module ProductQueries
      PRODUCT_QUERY_DETAIL_SORTS = RawOzon::ProductQueryDetail::TOP_ORDER_BY_VALUES

      # POST /v1/analytics/product-queries        — SKU 级搜索汇总
      # POST /v1/analytics/product-queries/details — 词级搜索明细（每 SKU 最多 15 词）
      def sync_product_queries
        sync_product_queries_for(request_end_offset: 0)
      end

      def sync_product_queries_through_friday
        sync_product_queries_for(request_end_offset: 2)
      end

      private

      def sync_product_queries_for(request_end_offset:)
        skus = RawOzon::Product.where(account_id: @account.id)
                               .filter_map do |product|
                                 sku = product.raw_json&.dig('sku').to_i
                                 sku.to_s if sku.positive?
                               end
                               .uniq
        return 0 if skus.empty?

        totals = { ok: 0, summaries: 0, details: 0, weeks: 0, failed_weeks: [] }
        completed_product_query_weeks.each do |week_start, week_end|
          request_end = week_end - request_end_offset.days
          begin
            counts = sync_product_query_week(skus, week_start:, week_end:, request_end:)
            totals[:summaries] += counts[:summaries]
            totals[:details] += counts[:details]
            totals[:weeks] += 1
          rescue OzonClient::ApiError => e
            totals[:failed_weeks] << { period_from: week_start, period_to: week_end, error: e.message }
            log "  ! product queries #{week_start}..#{request_end} skipped: #{e.message}", level: :warn
          end
        end

        totals[:ok] = totals[:summaries] + totals[:details]
        totals
      end

      def completed_product_query_weeks
        first_week = @from.to_date.beginning_of_week(:monday)
        # Fetch the newly completed week immediately, then let the recurring
        # midweek refresh replace Ozon's still-settling 1-2 day figures.
        last_week_end = Date.current.beginning_of_week(:monday) - 1.day
        return [] if first_week > last_week_end

        first_week.step(last_week_end, 7).map { |week_start| [week_start, week_start + 6.days] }
      end

      def sync_product_query_week(skus, week_start:, week_end:, request_end:)
        q_from = Time.utc(week_start.year, week_start.month, week_start.day).iso8601
        q_to = Time.utc(request_end.year, request_end.month, request_end.day, 23, 59, 59).iso8601
        synced_at = Time.current
        summary_rows = []
        detail_rows = []

        skus.each_slice(200) do |slice|
          summary_rows.concat(fetch_product_query_summaries(slice, q_from:, q_to:, week_start:, week_end:, synced_at:))
          PRODUCT_QUERY_DETAIL_SORTS.each do |top_order_by|
            detail_rows.concat(fetch_product_query_details(
              slice, q_from:, q_to:, week_start:, week_end:, synced_at:, top_order_by:
            ))
            sleep 1
          end
          sleep 1
        end

        summary_rows = summary_rows.index_by { |row| row[:sku] }.values
        detail_rows = detail_rows.group_by { |row| [row[:sku], row[:query], row[:top_order_by]] }.map do |_key, rows|
          rows.min_by { |row| row[:top_order_rank] }
        end

        RawOzon::ProductQuery.transaction do
          RawOzon::ProductQuery.where(account_id: @account.id, period_from: week_start, period_to: week_end).delete_all
          RawOzon::ProductQueryDetail.where(account_id: @account.id, period_from: week_start, period_to: week_end).delete_all
          RawOzon::ProductQuery.upsert_all(summary_rows, unique_by: :idx_ozon_product_queries_unique) if summary_rows.any?
          RawOzon::ProductQueryDetail.upsert_all(detail_rows, unique_by: :idx_ozon_product_query_details_unique) if detail_rows.any?
        end

        { summaries: summary_rows.size, details: detail_rows.size }
      end

      def fetch_product_query_summaries(skus, q_from:, q_to:, week_start:, week_end:, synced_at:)
        fetch_product_query_pages('/v1/analytics/product-queries', 'items', {
          date_from: q_from, date_to: q_to, skus:, page_size: 1000,
          sort_by: 'BY_SEARCHES', sort_dir: 'DESCENDING'
        }).map do |item|
          {
            account_id: @account.id, period_from: week_start, period_to: week_end,
            sku: item['sku'].to_i, offer_id: item['offer_id'], name: item['name'],
            category: item['category'], currency: item['currency'],
            unique_search_users: item['unique_search_users'].to_i,
            unique_view_users: item['unique_view_users']&.to_i,
            position: item['position'], view_conversion: item['view_conversion'],
            gmv: item['gmv'], synced_at:
          }
        end
      end

      def fetch_product_query_details(skus, q_from:, q_to:, week_start:, week_end:, synced_at:, top_order_by:)
        fetch_product_query_pages('/v1/analytics/product-queries/details', 'queries', {
          date_from: q_from, date_to: q_to, skus:, limit_by_sku: 15, page_size: 100,
          sort_by: top_order_by,
          sort_dir: top_order_by == 'BY_POSITION' ? 'ASCENDING' : 'DESCENDING'
        }).map do |query|
          {
            account_id: @account.id, period_from: week_start, period_to: week_end,
            sku: query['sku'].to_i, query: query['query'].to_s,
            query_index: query['query_index'].to_i,
            top_order_by:, top_order_rank: query['query_index'].to_i,
            currency: query['currency'],
            unique_search_users: query['unique_search_users'].to_i,
            unique_view_users: query['unique_view_users']&.to_i,
            position: query['position'], view_conversion: query['view_conversion'],
            order_count: query['order_count'].to_i, gmv: query['gmv'], synced_at:
          }
        end
      end

      def fetch_product_query_pages(path, items_key, body)
        page = 0
        rows = []
        loop do
          response = @client.post(path, body.merge(page:))
          items = Array(response[items_key])
          rows.concat(items)
          page_count = response['page_count'].to_i
          break if items.empty? || (page_count.positive? ? page + 1 >= page_count : items.size < body[:page_size])

          page += 1
        end
        rows
      end
    end
  end
end
