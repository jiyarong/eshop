module RawWb
  module Syncs
    module Stocks
      # GET /api/v1/supplier/stocks — statistics-api (seller warehouse stocks, full replace)
      def sync_stocks
        data = @client.get(:statistics, '/api/v1/supplier/stocks', dateFrom: @from.iso8601)
        rows = Array(data)
        return 0 if rows.empty?

        warehouse_cache = {}
        records = rows.filter_map do |r|
          wh_name = r['warehouseName'].to_s.strip
          next if wh_name.blank?

          wh_id = warehouse_cache[wh_name] ||= find_or_create_warehouse_by_name(wh_name)
          next if wh_id.nil?

          {
            account_id:   @account.id,
            warehouse_id: wh_id,
            barcode:      r['barcode'].to_s,
            quantity:     r['quantity'].to_i,
          }
        end
        return 0 if records.empty?

        now = Time.current
        records.each { |r| r[:updated_at] = now }
        RawWb::Stock.upsert_all(records,
          unique_by: :idx_raw_wb_stocks_unique,
          update_only: %i[quantity updated_at],
          record_timestamps: false)
        records.size
      end
    end
  end
end
