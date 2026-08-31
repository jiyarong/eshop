module RawOzon
  module Syncs
    module SupplyOrders
      SUPPLY_STATES = %w[
        DATA_FILLING
        READY_TO_SUPPLY
        ACCEPTED_AT_SUPPLY_WAREHOUSE
        IN_TRANSIT
        ACCEPTANCE_AT_STORAGE_WAREHOUSE
        REPORTS_CONFIRMATION_AWAITING
        REPORT_REJECTED
        COMPLETED
        REJECTED_AT_SUPPLY_WAREHOUSE
        CANCELLED
        OVERDUE
      ].freeze

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

          payloads = orders.map { |order| build_supply_order_payload(order, synced_at) }
          rows = payloads.map { |payload| payload.fetch(:order) }
          existing = RawOzon::SupplyOrder
            .where(account_id: @account.id, supply_order_id: rows.map { |row| row[:supply_order_id] })
            .index_by(&:supply_order_id)
          changes = rows.filter_map do |row|
            previous = existing[row[:supply_order_id]]
            next if previous&.status == row[:status]

            { previous_status: previous&.status, previous_items: previous&.items, row: row }
          end

          RawOzon::SupplyOrder.transaction do
            RawOzon::SupplyOrder.upsert_all(
              rows,
              unique_by: [:account_id, :supply_order_id],
              update_only: %i[status timeslot items raw_json created_at synced_at]
            ) if rows.any?
            replace_supply_order_items(payloads, synced_at)
            Ec::SupplyOrderChangeRecorder.record(account: @account, changes: changes, operated_at: synced_at)
          end
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
            filter:   { states: SUPPLY_STATES, created_at_from: '2025-01-01T00:00:00Z' },
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

      def fetch_bundle_items(bundle_id)
        items = []
        last_id = ""

        loop do
          resp = @client.post("/v1/supply-order/bundle", {
            bundle_ids: [bundle_id], limit: 100, last_id: last_id
          })
          items.concat(Array(resp["items"]))
          break unless resp["has_next"]

          last_id = resp["last_id"].to_s
          break if last_id.empty?
          sleep 0.3
        end

        items
      end

      def build_supply_order_payload(o, synced_at)
        supply_states = Array(o['supplies']).map { |s| s['state'] }.uniq
        status        = o['state'].presence || supply_states.first
        cancelled     = status == 'CANCELLED'
        details       = cancelled ? [] : build_supply_order_items(o)
        items         = cancelled ? nil : details.each_with_object(Hash.new(0)) do |detail, totals|
          totals[detail.fetch(:platform_sku_id).to_s] += detail.fetch(:quantity)
        end
        order = {
          account_id:      @account.id,
          supply_order_id: o['order_id'].to_s,
          status:          status,
          timeslot:        o['timeslot'],
          items:           items,
          raw_json:        o,
          created_at:      o['created_date'],
          synced_at:       synced_at,
        }
        { order: order, details: details }
      end

      def build_supply_order_items(order)
        Array(order["supplies"]).flat_map do |supply|
          bundle_id = supply["bundle_id"].to_s
          next [] if bundle_id.empty? || supply["supply_id"].blank? || supply["state"] == "CANCELLED"

          fetch_bundle_items(bundle_id).map do |item|
            warehouse = supply["storage_warehouse"].to_h
            {
              ozon_supply_id: supply["supply_id"], bundle_id: bundle_id, state: supply["state"],
              platform_sku_id: item["sku"], quantity: item["quantity"].to_i,
              macrolocal_cluster_id: supply["macrolocal_cluster_id"],
              storage_warehouse_id: warehouse["warehouse_id"], storage_warehouse_name: warehouse["name"],
              storage_warehouse_address: warehouse["address"], is_crossdock: supply["is_crossdock"],
              raw_json: item
            }
          end
        end
      end

      def replace_supply_order_items(payloads, synced_at)
        orders_by_external_id = RawOzon::SupplyOrder
          .where(account_id: @account.id, supply_order_id: payloads.map { |payload| payload.dig(:order, :supply_order_id) })
          .index_by(&:supply_order_id)
        order_ids = orders_by_external_id.values.map(&:id)
        RawOzon::SupplyOrderItem.where(supply_order_id: order_ids).delete_all

        rows = payloads.flat_map do |payload|
          supply_order = orders_by_external_id.fetch(payload.dig(:order, :supply_order_id))
          payload.fetch(:details).map do |detail|
            detail.merge(supply_order_id: supply_order.id, synced_at: synced_at, created_at: synced_at, updated_at: synced_at)
          end
        end
        RawOzon::SupplyOrderItem.insert_all!(rows) if rows.any?
      end
    end
  end
end
