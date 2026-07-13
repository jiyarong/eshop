module RawWb
  module Syncs
    module SupplyItems
      # FBW 送货明细（supplies-api 域名，与 marketplace-api 不同）
      # Step 1: POST /api/v1/supplies — 拉全量 FBW 送货单列表（无日期/状态过滤）
      # Step 2: GET  /api/v1/supplies/{id}/goods — 每单的货物明细
      def sync_supply_items
        supplies = fetch_fbw_supply_refs
        return 0 if supplies.empty?

        total = 0
        supplies.each do |supply|
          items = fetch_supply_goods(supply[:id], is_preorder: supply[:is_preorder])
          next if items.empty?

          rows = items.filter_map { |item| build_supply_item(supply[:id], item) }
          if rows.any?
            RawWb::SupplyItem.where(account_id: @account.id, wb_supply_id: supply[:id]).delete_all
            RawWb::SupplyItem.insert_all(rows)
            total += rows.size
          end
          sleep 0.3
        end

        total
      end

      private

      def fetch_fbw_supply_refs
        resp = @client.post(:supplies, '/api/v1/supplies', {
          dates:  [{ from: '2023-01-01', till: Date.current.to_s, type: 'createDate' }],
          limit:  1000,
        })
        items = resp.is_a?(Array) ? resp : Array(resp['supplies'] || [])
        upsert_supplies_from_v1(items)
        items.filter_map { |s| supply_ref(s) }
      rescue RawWb::WbClient::ApiError => e
        log "  ⚠ fetch_fbw_supply_refs failed: #{e.message}", level: :warn
        []
      end

      def upsert_supplies_from_v1(items)
        rows = items.map do |s|
          {
            account_id:       @account.id,
            wb_supply_id:     supply_lookup_id(s),
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

      def fetch_supply_goods(supply_id, is_preorder:)
        resp = @client.get(:supplies, "/api/v1/supplies/#{supply_id}/goods", { limit: 1000, isPreorderID: is_preorder })
        resp.is_a?(Array) ? resp : Array(resp['goods'] || [])
      rescue RawWb::WbClient::ApiError => e
        log "  ⚠ fetch_supply_goods #{supply_id} failed: #{e.message}", level: :warn
        []
      end

      def supply_ref(supply)
        id = supply_lookup_id(supply)
        return if id.blank?

        { id: id, is_preorder: supply['supplyID'].blank? && supply['id'].blank? }
      end

      def supply_lookup_id(supply)
        (supply['supplyID'].presence || supply['id'].presence || supply['preorderID'].presence)&.to_s
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
