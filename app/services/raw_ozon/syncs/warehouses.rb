module RawOzon
  module Syncs
    module Warehouses
      # POST /v2/warehouse/list
      def sync_warehouses
        resp  = @client.post('/v2/warehouse/list', { limit: 100 })
        items = Array(resp['result'] || resp['warehouses'] || resp)
        rows  = items.map { |w| build_warehouse(w) }
        RawOzon::Warehouse.upsert_all(rows, unique_by: [:account_id, :warehouse_id]) if rows.any?
        rows.size
      end

      private

      def build_warehouse(w)
        {
          account_id:               @account.id,
          warehouse_id:             w['warehouse_id'],
          name:                     w['name'],
          is_rfbs:                  w['is_rfbs'] || false,
          has_entrusted_acceptance: w['has_entrusted_acceptance'] || false,
          status:                   w['status'],
          raw_json:                 w,
          synced_at:                Time.current,
        }
      end
    end
  end
end
