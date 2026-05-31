module RawOzon
  module Syncs
    module Returns
      # POST /v1/returns/list (last_id pagination, FBO+FBS 统一)
      def sync_returns
        synced_at = Time.current
        fetch_last_id_paginated(
          path:      '/v1/returns/list',
          body:      { filter: {} },
          items_key: 'returns',
          limit:     100,
          initial_last_id: 0,
        ) do |items|
          rows = items.map { |r| build_return(r, synced_at) }
          RawOzon::Return.upsert_all(rows, unique_by: [:account_id, :return_id],
                                     update_only: %i[visual_status storage compensation_status synced_at]) if rows.any?
        end
      end

      private

      def build_return(r, synced_at)
        product = r['product'] || {}
        {
          account_id:          @account.id,
          return_id:           r['id'],
          return_schema:       r['schema'],
          return_type:         r['type'],
          return_reason_name:  r['return_reason_name'],
          posting_number:      r['posting_number'],
          order_id:            r['order_id'],
          order_number:        r['order_number'],
          ozon_sku:            product['sku'],
          offer_id:            product['offer_id'],
          product_name:        product['name'],
          quantity:            product['quantity'] || 1,
          price:               (product['price'].is_a?(Hash) ? product['price']['price'] : product['price']).to_f,
          place:               r['place'],
          target_place:        r['target_place'],
          storage:             r['storage'],
          visual_status:       r.dig('visual', 'status'),
          compensation_status: r['compensation_status'],
          raw_json:            r,
          synced_at:           synced_at,
        }
      end
    end
  end
end
