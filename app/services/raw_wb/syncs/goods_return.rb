module RawWb
  module Syncs
    module GoodsReturn
      ENDPOINT = "/api/analytics/v1/item-returns".freeze
      STATUSES = %w[active archive].freeze
      PAGE_SIZE = 1000

      # GET /api/analytics/v1/item-returns — seller-analytics-api
      # Keep 31-day chunks so the existing 90-day status catch-up remains bounded.
      def sync_goods_return
        result    = empty_sync_count
        synced_at = Time.current

        date_chunks(chunk_days: 31).each do |chunk_from, chunk_to|
          items = STATUSES.flat_map do |status|
            fetch_goods_return_status(chunk_from, chunk_to, status: status).map { |item| [item, status] }
          end
          next if items.empty?

          rows = items
            .map { |item, status| build_goods_return(item, status:, synced_at:) }
            .index_by { |row| row[:shk_id] }
            .values
          merge_sync_count!(result, upsert_count_result(rows, model: RawWb::GoodsReturn, unique_key: %i[account_id shk_id]))
          RawWb::GoodsReturn.upsert_all(rows, unique_by: %i[account_id shk_id],
            update_only: %i[order_id status is_status_active completed_dt expired_dt ready_to_return_dt synced_at])
          raw_records = RawWb::GoodsReturn.where(account_id: @account.id, shk_id: rows.pluck(:shk_id))
          Ec::Returns::Sync.call(raw_records: raw_records)
          sleep 65  # 1 req/min rate limit on seller-analytics-api
        end

        result
      end

      private

      def fetch_goods_return_status(from, to, status:)
        items = []
        offset = 0

        loop do
          data = fetch_goods_return_page(from, to, status:, offset:)
          page = Array(data["report"])
          items.concat(page)
          total = data["count"].to_i
          break if page.empty? || items.size >= total

          offset += PAGE_SIZE
        end

        items
      end

      def fetch_goods_return_page(from, to, status:, offset:, retries: 0)
        @client.get(
          :seller_analytics,
          ENDPOINT,
          dateFrom: from.iso8601,
          dateTo: to.iso8601,
          status: status,
          limit: PAGE_SIZE,
          offset: offset
        )
      rescue RawWb::WbClient::RetryableError => e
        raise if retries >= 3
        wait = 65
        log "  ⏳ item-returns 429, waiting #{wait}s before retry (#{retries + 1}/3)...", level: :warn
        sleep wait
        fetch_goods_return_page(from, to, status:, offset:, retries: retries + 1)
      end

      def build_goods_return(r, status:, synced_at:)
        {
          account_id:          @account.id,
          shk_id:              r['shkId'],
          order_id:            r['orderId'].presence&.then { |v| v.to_i > 0 ? v.to_i : nil },
          nm_id:               r['nmId'],
          barcode:             r['sku'],
          brand:               r['brand'],
          subject_name:        r['subjectName'],
          tech_size:           r['techSize'],
          return_type:         r['returnType'],
          reason:              nil,
          status:              r['returnStatus'],
          is_status_active:    status == "active" ? 1 : 0,
          srid:                r['srid'].presence,
          sticker_id:          r['stickerId'],
          order_dt:            r['orderDt'].presence,
          ready_to_return_dt:  r['readyToReturnDt'].presence,
          completed_dt:        r['completedDt'].presence,
          expired_dt:          r['expiredDt'].presence,
          dst_office_id:       r['dstOfficeId'],
          dst_office_address:  r['dstOfficeAddress'],
          synced_at:           synced_at,
        }
      end
    end
  end
end
