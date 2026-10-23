module RawWb
  module Syncs
    module Supplies
      FBS_SUPPLY_ORDER_REQUEST_INTERVAL = 0.25 # FBS endpoints allow 300 requests/minute

      # GET /api/v3/supplies — marketplace-api (cursor pagination)
      # Then links the supplies closed inside the lookback window to their orders and stamps the
      # FBS fulfillments' shipped_at. WB only serves a supply's orders for about the last 4 months, so
      # supplies are linked while they are recent; older links are never recoverable.
      # Result: created = new supply-order links, updated = fulfillments whose shipped_at changed.
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

        links, failures = sync_fbs_supply_orders
        shipped = Ec::OrderImport::WbShippedAt.call(account_id: @account.id)
        raise "Failed to fetch orders of FBS supplies: #{failures.join(', ')}" if failures.any?

        { ok: total, fetched: total, created: links, updated: shipped }
      end

      private

      # GET /api/marketplace/v3/supplies/{supplyId}/order-ids for every closed FBS supply of the lookback window.
      def sync_fbs_supply_orders
        created  = 0
        failures = []

        closed_fbs_supplies.find_each do |supply|
          resp      = @client.get(:marketplace, "/api/marketplace/v3/supplies/#{supply.wb_supply_id}/order-ids")
          order_ids = RawWb::Order.where(account_id: @account.id, wb_order_id: Array(resp['orderIds'])).pluck(:id)
          if order_ids.any?
            before = RawWb::SupplyOrder.where(supply_id: supply.id).count
            RawWb::SupplyOrder.insert_all(order_ids.map { |order_id| { supply_id: supply.id, order_id: order_id } },
              unique_by: %i[supply_id order_id])
            created += RawWb::SupplyOrder.where(supply_id: supply.id).count - before
          end
        rescue WbClient::ApiError => e
          failures << "#{supply.wb_supply_id} (#{e.message})"
        ensure
          sleep FBS_SUPPLY_ORDER_REQUEST_INTERVAL
        end

        [created, failures]
      end

      def closed_fbs_supplies
        RawWb::Supply
          .where(account_id: @account.id, is_done: true)
          .where("wb_supply_id LIKE 'WB-GI%'")
          .where(closed_at: @from.beginning_of_day..)
      end

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
