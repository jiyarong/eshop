module RawOzon
  module Syncs
    module ProductPrices
      # POST /v5/product/info/prices (cursor pagination)
      def sync_product_prices
        synced_at = Time.current
        fetch_cursor_paginated(
          path:      '/v5/product/info/prices',
          body:      { filter: {} },
          items_key: 'items',
          limit:     100,
        ) do |items|
          rows = items.map { |p| build_price(p, synced_at) }
          RawOzon::ProductPrice.upsert_all(rows, unique_by: [:account_id, :ozon_product_id]) if rows.any?
        end
      end

      private

      def build_price(p, synced_at)
        price  = p.dig('price', 'price').to_f
        old_p  = p.dig('price', 'old_price').to_f
        mkt_p  = p.dig('price', 'marketing_price').to_f
        min_p  = p.dig('price', 'min_price').to_f
        {
          account_id:      @account.id,
          ozon_product_id: p['product_id'],
          offer_id:        p['offer_id'],
          price:           price,
          old_price:       old_p.positive? ? old_p : nil,
          marketing_price: mkt_p.positive? ? mkt_p : nil,
          min_price:       min_p.positive? ? min_p : nil,
          currency_code:   p.dig('price', 'currency_code'),
          commissions:     p['commissions'],
          acquiring:       p['acquiring'],
          volume_weight:   p['volume_weight'],
          raw_json:        p,
          synced_at:       synced_at,
        }
      end
    end
  end
end
