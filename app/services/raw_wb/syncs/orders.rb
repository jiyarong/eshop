module RawWb
  module Syncs
    module Orders
      ORDER_STATUS_FETCH_BATCH_SIZE = 1000
      ORDER_STATUS_UPDATE_BATCH_SIZE = 500
      FINAL_SUPPLIER_STATUSES = %w[complete returned].freeze
      FINAL_WB_STATUSES = %w[cancel cancelled returned].freeze
      NORMALIZED_ORDER_STATUS_SQL = <<~SQL.squish
        CASE
          WHEN v.wb_status = 'cancelled' OR v.supplier_status LIKE '%cancel%' THEN 'cancelled'
          WHEN v.supplier_status = 'complete' THEN 'delivered'
          WHEN v.supplier_status = 'returned' OR v.wb_status = 'returned' THEN 'returned'
          WHEN v.supplier_status IN ('new', 'confirm') THEN 'processing'
          ELSE 'unknown'
        END
      SQL

      # GET /api/v3/orders — marketplace-api (cursor pagination, max 30-day window per request).
      # Uses date_chunks to iterate the full @from..today range so long lookbacks work correctly.
      def sync_orders
        result    = empty_sync_count
        synced_at = Time.current

        date_chunks(chunk_days: 30).each do |chunk_from, chunk_to|
          merge_sync_count!(result, fetch_orders_window(chunk_from, chunk_to, synced_at))
          sleep 1
        end

        refresh_order_statuses
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

      def refresh_order_statuses
        order_ids = RawWb::Order
          .where(account_id: @account.id)
          .where.not(supplier_status: FINAL_SUPPLIER_STATUSES)
          .where.not(wb_status: FINAL_WB_STATUSES)
          .where.not("supplier_status LIKE ?", "%cancel%")
          .pluck(:wb_order_id)
        return if order_ids.empty?

        order_ids.each_slice(ORDER_STATUS_FETCH_BATCH_SIZE) do |chunk|
          resp = @client.post(:marketplace, "/api/v3/orders/status", { orders: chunk })
          api_orders = resp["orders"] || []
          api_orders.each_slice(ORDER_STATUS_UPDATE_BATCH_SIZE) { |batch| bulk_update_order_statuses(batch) }
          sleep 1
        end
      end

      def bulk_update_order_statuses(api_orders)
        return if api_orders.empty?

        values_sql = api_orders.map do |order|
          supplier_status = ActiveRecord::Base.connection.quote(order["supplierStatus"])
          wb_status = ActiveRecord::Base.connection.quote(order["wbStatus"])

          "(#{order["id"].to_i}, #{supplier_status}, #{wb_status})"
        end.join(", ")

        update_ec_order_statuses(values_sql)
        update_ec_fulfillment_statuses(values_sql)
        update_raw_order_statuses(values_sql)
      end

      def update_raw_order_statuses(values_sql)
        sql = <<~SQL
          UPDATE raw_wb_orders AS o
          SET supplier_status = v.supplier_status,
              wb_status = v.wb_status,
              updated_at = NOW()
          FROM (VALUES #{values_sql}) AS v(wb_order_id, supplier_status, wb_status)
          WHERE o.account_id = #{@account.id.to_i}
            AND o.wb_order_id = v.wb_order_id
            AND (o.supplier_status IS NULL OR o.supplier_status NOT IN (#{quoted_statuses(FINAL_SUPPLIER_STATUSES)}))
            AND (o.wb_status IS NULL OR o.wb_status NOT IN (#{quoted_statuses(FINAL_WB_STATUSES)}))
            AND (o.supplier_status IS NULL OR o.supplier_status NOT LIKE '%cancel%')
        SQL

        ActiveRecord::Base.connection.execute(sql)
      end

      def update_ec_order_statuses(values_sql)
        sql = <<~SQL
          UPDATE ec_orders AS eo
          SET order_status = #{NORMALIZED_ORDER_STATUS_SQL},
              source_status = v.wb_status,
              source_substatus = v.supplier_status,
              updated_at = NOW()
          FROM (VALUES #{values_sql}) AS v(wb_order_id, supplier_status, wb_status)
          INNER JOIN raw_wb_orders AS rwo
            ON rwo.account_id = #{@account.id.to_i}
           AND rwo.wb_order_id = v.wb_order_id
          INNER JOIN ec_order_source_links AS link
            ON link.source_type = 'RawWb::Order'
           AND link.source_id = rwo.id
           AND link.source_role = 'primary'
          WHERE eo.id = link.order_id
            AND eo.platform = 'wb'
            AND (rwo.supplier_status IS NULL OR rwo.supplier_status NOT IN (#{quoted_statuses(FINAL_SUPPLIER_STATUSES)}))
            AND (rwo.wb_status IS NULL OR rwo.wb_status NOT IN (#{quoted_statuses(FINAL_WB_STATUSES)}))
            AND (rwo.supplier_status IS NULL OR rwo.supplier_status NOT LIKE '%cancel%')
        SQL

        ActiveRecord::Base.connection.execute(sql)
      end

      def update_ec_fulfillment_statuses(values_sql)
        sql = <<~SQL
          UPDATE ec_order_fulfillments AS fulfillment
          SET status = #{NORMALIZED_ORDER_STATUS_SQL},
              source_status = v.wb_status,
              source_substatus = v.supplier_status,
              updated_at = NOW()
          FROM (VALUES #{values_sql}) AS v(wb_order_id, supplier_status, wb_status)
          INNER JOIN raw_wb_orders AS rwo
            ON rwo.account_id = #{@account.id.to_i}
           AND rwo.wb_order_id = v.wb_order_id
          WHERE fulfillment.raw_source_type = 'RawWb::Order'
            AND fulfillment.raw_source_id = rwo.id
            AND fulfillment.platform = 'wb'
            AND (rwo.supplier_status IS NULL OR rwo.supplier_status NOT IN (#{quoted_statuses(FINAL_SUPPLIER_STATUSES)}))
            AND (rwo.wb_status IS NULL OR rwo.wb_status NOT IN (#{quoted_statuses(FINAL_WB_STATUSES)}))
            AND (rwo.supplier_status IS NULL OR rwo.supplier_status NOT LIKE '%cancel%')
        SQL

        ActiveRecord::Base.connection.execute(sql)
      end

      def quoted_statuses(statuses)
        statuses.map { |status| ActiveRecord::Base.connection.quote(status) }.join(", ")
      end
    end
  end
end
