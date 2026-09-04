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
          customer_prices = customer_prices_for(items)
          rows = items.map do |p|
            build_price(p, synced_at, customer_price: customer_prices[p['product_id'].to_i])
          end
          record_ozon_price_changes(rows)
          RawOzon::ProductPrice.upsert_all(rows, unique_by: [:account_id, :ozon_product_id]) if rows.any?
        end
      end

      private

      def record_ozon_price_changes(rows)
        existing = RawOzon::ProductPrice
          .where(account_id: @account.id, ozon_product_id: rows.map { |row| row[:ozon_product_id] })
          .index_by(&:ozon_product_id)

        rows.each do |row|
          price = existing[row[:ozon_product_id]]
          next unless price

          sku_product = ozon_price_sku_product(row[:ozon_product_id])
          next unless sku_product

          Ec::ListingChangeRecorder.record(
            sku_product: sku_product,
            operation_type: "listing_pricing",
            before: ozon_price_snapshot(price.attributes.symbolize_keys),
            after: ozon_price_snapshot(row)
          )
        end
      end

      def ozon_price_snapshot(values)
        values.slice(
          :price,
          :customer_price,
          :old_price,
          :marketing_price,
          :min_price,
          :currency_code,
          :commissions,
          :acquiring,
          :volume_weight
        )
      end

      def ozon_price_sku_product(product_id)
        store = @ozon_price_store ||= Ec::Store.find_by(platform: 'ozon', ozon_raw_account_id: @account.id)
        return unless store

        Ec::SkuProduct.includes(:sku, :store).find_by(store: store, product_id: product_id.to_s)
      end

      def customer_prices_for(items)
        sku_by_product_id = RawOzon::Product
          .where(account_id: @account.id, ozon_product_id: items.filter_map { |item| item['product_id'] })
          .pluck(:ozon_product_id, :raw_json)
          .to_h { |product_id, raw_json| [product_id.to_i, raw_json.to_h['sku']] }
        skus = sku_by_product_id.values.compact
        return {} if skus.empty?

        response = @client.post('/v1/product/prices/details', { skus: skus.map(&:to_s) })
        Array(response['prices']).each_with_object({}) do |item, result|
          amount = item.dig('customer_price', 'amount').to_f
          next unless amount.positive?

          product_id = sku_by_product_id.key(item['sku'].to_i)
          result[product_id] = amount if product_id
        end
      rescue OzonClient::ApiError, OzonClient::RetryableError => error
        log "Could not load Ozon customer prices: #{error.message}", level: :warn
        {}
      end

      def build_price(p, synced_at, customer_price: nil)
        price  = p.dig('price', 'price').to_f
        old_p  = p.dig('price', 'old_price').to_f
        mkt_p  = (p.dig('price', 'marketing_seller_price') || p.dig('price', 'marketing_price')).to_f
        min_p  = p.dig('price', 'min_price').to_f
        {
          account_id:      @account.id,
          ozon_product_id: p['product_id'],
          offer_id:        p['offer_id'],
          price:           price,
          customer_price:  customer_price,
          old_price:       old_p.positive? ? old_p : nil,
          marketing_price: mkt_p.positive? ? mkt_p : nil,
          min_price:       min_p.positive? ? min_p : nil,
          currency_code:   p.dig('price', 'currency_code'),
          commissions:     p['commissions'],
          acquiring:       p['acquiring'].present? ? BigDecimal(p['acquiring'].to_s) : nil,
          volume_weight:   p['volume_weight'],
          raw_json:        p,
          synced_at:       synced_at,
        }
      end
    end
  end
end
