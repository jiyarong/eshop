module RawOzon
  module Syncs
    module Returns
      # POST /v1/returns/list — uses has_next + items.last['id'] pagination (not resp['last_id'])
      def sync_returns
        synced_at = Time.current
        last_id   = 0
        total     = 0
        loop do
          resp  = @client.post('/v1/returns/list', { filter: {}, limit: 100, last_id: last_id })
          items = Array(resp['returns'])
          break if items.empty?
          rows = items.map { |r| build_return(r, synced_at) }
          RawOzon::Return.upsert_all(rows, unique_by: [:account_id, :return_id],
                                     update_only: %i[visual_status storage compensation_status
                                                     return_date final_moment visual_change_moment synced_at])
          total  += items.size
          break unless resp['has_next']
          last_id = items.last['id']
          sleep 0.3
        end
        total
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
          place:                r['place'],
          target_place:         r['target_place'],
          storage:              r['storage'],
          visual_status:        r.dig('visual', 'status'),
          compensation_status:  r['compensation_status'],
          return_date:          r.dig('logistic', 'return_date').presence&.then { Time.parse(_1) rescue nil },
          final_moment:         r.dig('logistic', 'final_moment').presence&.then { Time.parse(_1) rescue nil },
          visual_change_moment: r.dig('visual', 'change_moment').presence&.then { Time.parse(_1) rescue nil },
          raw_json:             r,
          synced_at:            synced_at,
        }
      end
    end
  end
end
