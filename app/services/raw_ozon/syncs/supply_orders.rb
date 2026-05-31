module RawOzon
  module Syncs
    module SupplyOrders
      # 三步链：
      # Step 1: POST /v3/supply-order/list  → order_ids（last_id 翻页）
      # Step 2: POST /v3/supply-order/get   → 完整 supply order 对象（每批 50）
      # Step 3: POST /v1/supply-order/bundle → {sku: quantity}（每个 order 单独查，避免混批）
      def sync_supply_orders
        synced_at = Time.current
        order_ids = fetch_all_supply_order_ids
        return 0 if order_ids.empty?

        total = 0
        order_ids.each_slice(50) do |batch_ids|
          orders = fetch_supply_order_details(batch_ids)
          next if orders.empty?

          rows = orders.map { |o| build_supply_order(o, synced_at) }
          RawOzon::SupplyOrder.upsert_all(rows, unique_by: [:account_id, :supply_order_id],
                                          update_only: %i[status timeslot items raw_json synced_at]) if rows.any?
          total += rows.size
          sleep 0.5
        end

        total
      end

      private

      def fetch_all_supply_order_ids
        order_ids = []
        last_id   = ''
        limit     = 50

        loop do
          resp = @client.post('/v3/supply-order/list', {
            filter:   { states: %w[COMPLETED CANCELLED], created_at_from: '2025-01-01T00:00:00Z' },
            limit:    limit,
            last_id:  last_id,
            sort_by:  'ORDER_CREATION',
            sort_dir: 'DESC',
          })
          ids = Array(resp['order_ids'])
          break if ids.empty?

          order_ids.concat(ids)
          last_id = resp['last_id'].to_s
          break if last_id.empty? || ids.size < limit
          sleep 0.5
        end

        order_ids
      end

      def fetch_supply_order_details(order_ids)
        resp = @client.post('/v3/supply-order/get', { order_ids: order_ids })
        Array(resp['orders'])
      end

      # 每个 order 单独拿 bundle items，避免混批无法区分归属
      def fetch_bundle_items_for_order(order)
        bundle_ids = Array(order['supplies']).map { |s| s['bundle_id'] }.compact
        return {} if bundle_ids.empty?

        result = {}
        bundle_ids.each_slice(10) do |batch|
          resp  = @client.post('/v1/supply-order/bundle', { bundle_ids: batch, limit: 100 })
          Array(resp['items']).each do |item|
            sku = item['sku'].to_s
            result[sku] = (result[sku] || 0) + item['quantity'].to_i
          end
          sleep 0.3
        end
        result
      end

      def build_supply_order(o, synced_at)
        # status 在 supplies[].state，不在顶层
        supply_states = Array(o['supplies']).map { |s| s['state'] }.uniq
        completed     = supply_states.include?('COMPLETED')
        items         = completed ? fetch_bundle_items_for_order(o) : nil
        {
          account_id:      @account.id,
          supply_order_id: o['order_id'].to_s,
          status:          supply_states.first,
          timeslot:        o['timeslot'],
          items:           items,
          raw_json:        o,
          created_at:      o['created_at'],
          synced_at:       synced_at,
        }
      end
    end
  end
end
