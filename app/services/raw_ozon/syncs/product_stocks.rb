module RawOzon
  module Syncs
    module ProductStocks
      # POST /v4/product/info/stocks (cursor pagination)
      def sync_product_stocks
        synced_at = Time.current
        fetch_cursor_paginated(
          path:      '/v4/product/info/stocks',
          body:      { filter: {} },
          items_key: 'items',
          limit:     100,
        ) do |items|
          rows = items.map { |p| build_stock(p, synced_at) }
          RawOzon::ProductStock.upsert_all(rows, unique_by: [:account_id, :ozon_product_id]) if rows.any?
        end
      end

      private

      def build_stock(p, synced_at)
        stocks = Array(p['stocks'])
        fbo    = stocks.find { |s| s['type'] == 'fbo' } || {}
        fbs    = stocks.find { |s| s['type'] == 'fbs' } || {}
        {
          account_id:          @account.id,
          ozon_product_id:     p['product_id'],
          offer_id:            p['offer_id'],
          present_fbo:         fbo['present'].to_i,
          reserved_fbo:        fbo['reserved'].to_i,
          present_fbs:         fbs['present'].to_i,
          reserved_fbs:        fbs['reserved'].to_i,
          stocks_by_warehouse: stocks,
          raw_json:            p,
          synced_at:           synced_at,
        }
      end
    end
  end
end
