module RawOzon
  module Syncs
    module Products
      # POST /v3/product/list (cursor pagination) → POST /v3/product/info/list (batch)
      def sync_products
        total    = 0
        last_id  = ''
        synced_at = Time.current

        loop do
          list_resp = @client.post('/v3/product/list', { filter: { visibility: 'ALL' }, limit: 100, last_id: last_id })
          items     = Array(list_resp.dig('result', 'items'))
          break if items.empty?

          product_ids = items.map { |i| i['product_id'] }.compact
          info_resp   = @client.post('/v3/product/info/list', { product_id: product_ids })
          info_items  = Array(info_resp['items'])

          rows = info_items.map { |p| build_product(p, synced_at) }
          RawOzon::Product.upsert_all(rows, unique_by: [:account_id, :ozon_product_id]) if rows.any?
          total   += rows.size
          last_id  = list_resp.dig('result', 'last_id').to_s
          break if last_id.empty? || items.size < 100
          sleep 0.5
        end

        total
      end

      private

      def build_product(p, synced_at)
        {
          account_id:              @account.id,
          ozon_product_id:         p['id'],
          offer_id:                p['offer_id'],
          name:                    p['name'],
          description_category_id: p['description_category_id'],
          type_id:                 p['type_id'],
          currency_code:           p['currency_code'],
          is_archived:             p['is_archived'] || false,
          is_autoarchived:         p['is_autoarchived'] || false,
          has_discounted_fbo_item: p['has_discounted_fbo_item'] || false,
          discounted_fbo_stocks:   p['discounted_fbo_stocks'] || 0,
          barcodes:                Array(p['barcodes']),
          images:                  p['images'],
          images360:               p['images360'],
          color_image:             p['color_image'],
          commissions:             p['commissions'],
          availabilities:          p['availabilities'],
          raw_json:                p,
          created_at:              p['created_at'],
          synced_at:               synced_at,
        }
      end
    end
  end
end
