module RawWb
  module Syncs
    module GoodsReturn
      # GET /api/v1/analytics/goods-return — seller-analytics-api
      # Max 31-day window per request; uses date_chunks to cover full @from..today range.
      def sync_goods_return
        result    = empty_sync_count
        synced_at = Time.current

        date_chunks(chunk_days: 31).each do |chunk_from, chunk_to|
          data  = @client.get(:seller_analytics, '/api/v1/analytics/goods-return',
                              dateFrom: chunk_from.iso8601, dateTo: chunk_to.iso8601)
          items = Array(data.is_a?(Hash) ? data['report'] || data['data'] : data)
          next if items.empty?

          rows = items.map { |r| build_goods_return(r, synced_at) }
          merge_sync_count!(result, upsert_count_result(rows, model: RawWb::GoodsReturn, unique_key: %i[account_id shk_id]))
          RawWb::GoodsReturn.upsert_all(rows, unique_by: %i[account_id shk_id],
            update_only: %i[order_id status is_status_active completed_dt expired_dt ready_to_return_dt synced_at])
          sleep 1
        end

        result
      end

      private

      def build_goods_return(r, synced_at)
        {
          account_id:          @account.id,
          shk_id:              r['shkId'],
          order_id:            r['orderId'].presence&.then { |v| v.to_i > 0 ? v.to_i : nil },
          nm_id:               r['nmId'],
          barcode:             r['barcode'],
          brand:               r['brand'],
          subject_name:        r['subjectName'],
          tech_size:           r['techSize'],
          return_type:         r['returnType'],
          reason:              r['reason'].presence,
          status:              r['status'],
          is_status_active:    r['isStatusActive'],
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
