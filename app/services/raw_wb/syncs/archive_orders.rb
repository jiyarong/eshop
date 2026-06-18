module RawWb
  module Syncs
    module ArchiveOrders
      # GET /api/marketplace/v3/fbs/orders/archive
      # Fetches completed/declined FBS orders that have left the active /api/v3/orders feed.
      # Required params: year, month, next (cursor from 0), limit (100..1000).
      # Pagination: follow `next` field in response until it returns 0.
      #
      # Key differences from sync_orders (v3/orders):
      #   - Segmented by year/month instead of dateFrom/dateTo unix timestamps
      #   - Fields nested: product.nmId, status.supplierStatus, priceInfo.price, etc.
      #   - No deliveryType field (always 'fbs')
      #   - Has final statuses (declined_by_client, complete, etc.) not available in active feed
      #
      # Usage (full backfill from given start_date):
      #   sync.sync_archive_orders(from_month: Date.new(2025, 1))
      #
      def sync_archive_orders(from_month: 12.months.ago.to_date)
        result    = empty_sync_count
        synced_at = Time.current

        start_date = from_month.beginning_of_month
        end_date   = Date.current.beginning_of_month
        current    = start_date

        while current <= end_date
          merge_sync_count!(result, fetch_archive_month(current.year, current.month, synced_at))
          current = current >> 1
          sleep 1
        end

        result
      end

      private

      def fetch_archive_month(year, month, synced_at)
        cursor = 0
        result = empty_sync_count

        loop do
          resp = @client.get(:marketplace, '/api/marketplace/v3/fbs/orders/archive',
                             year:  year,
                             month: month,
                             next:  cursor,
                             limit: 1000)
          orders = resp['orders'] || []
          break if orders.empty?

          rows = orders.map { |o| build_archive_order(o, synced_at) }
          RawWb::Order.upsert_all(rows,
                                  unique_by:        :wb_order_id,
                                  update_only:      archive_order_update_cols,
                                  record_timestamps: false)
          merge_sync_count!(result, upsert_count_result(rows, model: RawWb::Order, unique_key: :wb_order_id))

          cursor = resp['next'].to_i
          break if cursor.zero?
          sleep 1
        end

        result
      end

      def build_archive_order(o, synced_at)
        product    = o['product']    || {}
        status     = o['status']     || {}
        price_info = o['priceInfo']  || {}

        {
          account_id:      @account.id,
          wb_order_id:     o['id'],
          order_uid:       o['orderUid'],
          srid:            o['rid'],
          delivery_type:   'fbs',
          nm_id:           product['nmId'],
          chrt_id:         product['chrtId'],
          article:         product['article'],
          barcode:         Array(product['skus']).first,
          supplier_status: status['supplierStatus'] || 'new',
          wb_status:       status['wbStatus']       || 'waiting',
          price:           price_info['price'].to_f           / 100,
          converted_price: price_info['convertedPrice'].to_f  / 100,
          currency_code:   price_info['currencyCode'] || 643,
          warehouse_id:    nil,
          g_number:        nil,
          wb_office:       nil,
          required_meta:   o['metaDetails'] || [],
          optional_meta:   [],
          buyer_info:      nil,
          is_zero_order:   o['isZeroOrder'] || false,
          created_at:      o['createdAt'],
          updated_at:      Time.current,
          synced_at:       synced_at,
        }
      end

      # Only update status fields and meta on upsert — never overwrite g_number
      # which is backfilled separately via the stats API.
      def archive_order_update_cols
        %i[
          supplier_status wb_status
          required_meta is_zero_order
          updated_at synced_at
        ]
      end
    end
  end
end