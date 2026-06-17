module RawWb
  module Syncs
    module Supplies
      # GET /api/v3/supplies — marketplace-api (cursor pagination)
      def sync_supplies
        cursor = 0
        total  = 0

        loop do
          resp     = @client.get(:marketplace, '/api/v3/supplies', limit: 1000, next: cursor)
          supplies = Array(resp['supplies'] || resp)
          break if supplies.empty?

          rows = supplies.filter_map { |s| build_supply(s) }
          RawWb::Supply.upsert_all(rows, unique_by: :wb_supply_id,
            update_only: %i[name is_done closed_at scan_dt synced_at]) if rows.any?
          total  += rows.size
          cursor  = resp['next'].to_i
          break if cursor.zero?
        end

        total
      end

      private

      def build_supply(s)
        return nil if s['id'].blank?
        {
          account_id:        @account.id,
          wb_supply_id:      s['id'].to_s,
          name:              s['name'],
          is_done:           s['done'] || false,
          supply_created_at: s['createdAt'],
          closed_at:         s['closedAt'],
          scan_dt:           s['scanDt'],
          synced_at:         Time.current,
        }
      end
    end
  end
end
