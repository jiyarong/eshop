module RawWb
  module Syncs
    module FbsStocks
      # GET /api/v3/warehouses + POST /api/v3/stocks/{warehouseId}
      # 同步卖家自仓的 FBS 库存（可发货数量）。
      # 仅处理 deliveryType=1（FBS）的卖家仓库，忽略 DBS 仓库。
      def sync_fbs_stocks
        fbs_warehouses = @client.get(:marketplace, '/api/v3/warehouses')
          .select { |w| w['deliveryType'] == 1 }
        return 0 if fbs_warehouses.empty?

        barcode_to_nm = build_barcode_to_nm_map
        return 0 if barcode_to_nm.empty?

        total     = 0
        now       = Time.current
        barcodes  = barcode_to_nm.keys

        fbs_warehouses.each do |wh|
          barcodes.each_slice(1000) do |batch|
            resp   = @client.post(:marketplace, "/api/v3/stocks/#{wh['id']}", { skus: batch })
            stocks = resp['stocks'] || []
            next if stocks.empty?

            rows = stocks.filter_map do |s|
              nm_id = barcode_to_nm[s['sku']]
              next unless nm_id
              {
                account_id: @account.id,
                barcode:    s['sku'],
                nm_id:      nm_id,
                amount:     s['amount'].to_i,
                synced_at:  now,
                created_at: now,
                updated_at: now,
              }
            end

            if rows.any?
              RawWb::FbsStock.upsert_all(
                rows,
                unique_by: :idx_raw_wb_fbs_stocks_unique,
                update_only: %i[nm_id amount synced_at updated_at],
                record_timestamps: false,
              )
              total += rows.size
            end
          end
          sleep 1
        end

        total
      end

      private

      def build_barcode_to_nm_map
        sql = <<~SQL
          SELECT ps.barcode, p.nm_id
          FROM raw_wb_product_skus ps
          JOIN raw_wb_products p ON p.id = ps.product_id
          WHERE p.account_id = #{@account.id.to_i}
        SQL
        ActiveRecord::Base.connection.execute(sql)
          .each_with_object({}) { |r, h| h[r['barcode']] = r['nm_id'].to_i }
      end
    end
  end
end
