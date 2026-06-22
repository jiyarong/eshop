module RawWb
  module Syncs
    module StatsOrders
      # GET /api/v1/supplier/orders — statistics-api
      def sync_stats_orders
        data = @client.get(:statistics, '/api/v1/supplier/orders', dateFrom: @from.iso8601)
        rows = Array(data).filter_map { |r| build_stats_order(r) }
        return 0 if rows.empty?

        # Assign a deterministic synthetic srid to records missing one so all rows
        # can go through upsert_all and remain idempotent across repeated syncs.
        rows.each do |r|
          unless r[:srid].present?
            r[:srid] = "nosrid:#{r[:account_id]}:#{r[:g_number]}:#{r[:barcode]}:#{r[:order_date].to_s[0..9]}"
          end
        end

        rows = rows.uniq { |r| r[:srid] }
        result = upsert_count_result(rows, model: RawWb::StatsOrder, unique_key: %i[account_id srid])
        RawWb::StatsOrder.upsert_all(rows, unique_by: %i[account_id srid],
          update_only: stats_order_update_cols)

        # Backfill fields available only in Statistics orders into marketplace orders.
        srid_to_order_fields = rows.each_with_object({}) do |r, h|
          next if r[:srid].blank?

          fields = {}
          fields[:g_number] = r[:g_number] if r[:g_number].present?
          fields[:warehouse_type] = r[:warehouse_type] if r[:warehouse_type].present?
          h[r[:srid]] = fields if fields.any?
        end
        if srid_to_order_fields.any?
          srid_to_order_fields.each_slice(500) do |slice|
            slice.each do |srid, fields|
              scope = RawWb::Order.where(account_id: @account.id, srid: srid)
              scope.where(g_number: nil).update_all(g_number: fields[:g_number]) if fields[:g_number]
              scope.where(warehouse_type: nil).update_all(warehouse_type: fields[:warehouse_type]) if fields[:warehouse_type]
            end
          end
        end

        result
      end

      private

      def build_stats_order(r)
        return nil if r['date'].blank?
        {
          account_id:       @account.id,
          g_number:         r['gNumber'],
          order_date:       r['date'],
          last_change_date: r['lastChangeDate'],
          supplier_article: r['supplierArticle'],
          tech_size:        r['techSize'],
          barcode:          r['barcode'],
          total_price:      r['totalPrice'],
          discount_percent: r['discountPercent'],
          warehouse_name:   r['warehouseName'],
          warehouse_type:   r['warehouseType'],
          oblast:           r['oblast'],
          nm_id:            r['nmId'],
          subject:          r['subject'],
          category:         r['category'],
          brand:            r['brand'],
          is_cancel:        r['isCancel'],
          cancel_date:      r['cancelDate'].presence,
          order_type:       r['orderType'],
          srid:             r['srid'].presence,
          synced_at:        Time.current,
        }
      end

      def stats_order_update_cols
        %i[last_change_date warehouse_type is_cancel cancel_date synced_at]
      end
    end
  end
end
