module RawWb
  module Syncs
    module Orders
      # GET /api/v3/orders — marketplace-api (cursor pagination, max 30-day window per request).
      # Uses date_chunks to iterate the full @from..today range so long lookbacks work correctly.
      def sync_orders
        result    = empty_sync_count
        synced_at = Time.current

        date_chunks(chunk_days: 30).each do |chunk_from, chunk_to|
          merge_sync_count!(result, fetch_orders_window(chunk_from, chunk_to, synced_at))
          sleep 1
        end

        result
      end

      private

      def fetch_orders_window(chunk_from, chunk_to, synced_at)
        cursor = 0
        result = empty_sync_count

        loop do
          resp = @client.get(:marketplace, '/api/v3/orders',
                             limit:    1000,
                             next:     cursor,
                             dateFrom: chunk_from.to_time.to_i,
                             dateTo:   chunk_to.to_time.end_of_day.to_i)
          orders = resp['orders'] || []
          break if orders.empty?

          rows = orders.map { |o| build_order(o, synced_at) }
          merge_sync_count!(result, upsert_count_result(rows, model: RawWb::Order, unique_key: :wb_order_id))
          RawWb::Order.upsert_all(rows, unique_by: :wb_order_id, update_only: order_update_cols, record_timestamps: false)
          cursor  = resp['next'].to_i
          break if cursor.zero?
        end

        result
      end

      def build_order(o, synced_at)
        {
          account_id:      @account.id,
          wb_order_id:     o['id'],
          order_uid:       o['orderUid'],
          srid:            o['rid'],
          delivery_type:   o['deliveryType'] || 'fbs',
          nm_id:           o['nmId'],
          chrt_id:         o['chrtId'],
          article:         o['article'],
          barcode:         Array(o['skus']).first,
          supplier_status: o['supplierStatus'] || 'new',
          wb_status:       o['wbStatus'] || 'waiting',
          price:           o['price'].to_f / 100,
          converted_price: o['convertedPrice'].to_f / 100,
          currency_code:   o['currencyCode'] || 643,
          warehouse_id:    nil,
          g_number:        nil,
          wb_office:       Array(o['offices']).first,
          required_meta:   o['requiredMeta'] || [],
          optional_meta:   o['optionalMeta'] || [],
          buyer_info:      o['userInfo'],
          is_zero_order:   o['isZeroOrder'] || false,
          created_at:      o['createdAt'],
          updated_at:      Time.current,
          synced_at:       synced_at,
        }
      end

      def order_update_cols
        %i[
          order_uid srid delivery_type nm_id chrt_id article barcode
          supplier_status wb_status price converted_price currency_code
          wb_office required_meta optional_meta buyer_info is_zero_order
          updated_at synced_at created_at
        ]
      end
    end
  end
end
