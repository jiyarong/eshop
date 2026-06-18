module RawWb
  module Syncs
    module SupplyItems
      # FBW 送货明细（supplies-api 域名，与 marketplace-api 不同）
      # Step 1: POST /api/v1/supplies — 拉全量 FBW 送货单列表（无日期/状态过滤）
      # Step 2: GET  /api/v1/supplies/{id}/goods — 每单的货物明细
      def sync_supply_items
        supply_ids = fetch_fbw_supply_ids
        return 0 if supply_ids.empty?

        total = 0
        supply_ids.each do |supply_id|
          items = fetch_supply_goods(supply_id)
          next if items.empty?

          rows = items.filter_map { |item| build_supply_item(supply_id, item) }
          if rows.any?
            RawWb::SupplyItem.where(account_id: @account.id, wb_supply_id: supply_id).delete_all
            RawWb::SupplyItem.insert_all(rows)
            total += rows.size
          end
          sleep 0.3
        end

        total
      end

      private

      def fetch_fbw_supply_ids
        resp = @client.post(:supplies, '/api/v1/supplies', {
          dates:  [{ from: '2023-01-01', till: Date.current.to_s, type: 'createDate' }],
          limit:  1000,
        })
        items = resp.is_a?(Array) ? resp : Array(resp['supplies'] || [])
        upsert_supplies_from_v1(items)
        items.filter_map { |s| s['supplyID'] || s['id'] }
      rescue RawWb::WbClient::ApiError => e
        log "  ⚠ fetch_fbw_supply_ids failed: #{e.message}", level: :warn
        []
      end

      def upsert_supplies_from_v1(items)
        rows = items.map do |s|
          {
            account_id:       @account.id,
            wb_supply_id:     s['supplyID']&.to_s,
            preorder_id:      s['preorderID'],
            status_id:        s['statusID'],
            box_type_id:      s['boxTypeID'],
            is_box_on_pallet: s['isBoxOnPallet'],
            supply_created_at: s['createDate'],
            supply_date:      s['supplyDate'],
            fact_date:        s['factDate'],
            updated_at_wb:    s['updatedDate'],
            synced_at:        Time.current,
          }
        end
        RawWb::Supply.upsert_all(rows, unique_by: :idx_raw_wb_supplies_account_preorder,
          update_only: %i[wb_supply_id status_id box_type_id is_box_on_pallet
                          supply_date fact_date updated_at_wb synced_at])
      end

      def fetch_supply_goods(supply_id)
        resp = @client.get(:supplies, "/api/v1/supplies/#{supply_id}/goods", { limit: 1000 })
        resp.is_a?(Array) ? resp : Array(resp['goods'] || [])
      rescue RawWb::WbClient::ApiError => e
        log "  ⚠ fetch_supply_goods #{supply_id} failed: #{e.message}", level: :warn
        []
      end

      def build_supply_item(supply_id, item)
        nm_id = item['nmID'] || item['nmId']
        return nil if nm_id.blank?
        {
          account_id:   @account.id,
          wb_supply_id: supply_id.to_s,
          nm_id:        nm_id.to_i,
          quantity:     (item['quantity'] || 0).to_i,
          accepted_qty: (item['acceptedQuantity'] || 0).to_i,
          synced_at:    Time.current,
        }
      end
    end
  end
end
