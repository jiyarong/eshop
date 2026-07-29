module RawWb
  module Syncs
    module ProductPrices
      # GET /api/v2/list/goods/filter — discounts-prices-api (offset pagination)
      # Response: { "data": { "listGoods": [...] } }
      # Price is in sizes[0].price; top-level has discount and clubDiscount.
      def sync_product_prices
        offset = 0
        total  = 0
        limit  = 100

        loop do
          data  = @client.get(:discounts_prices, '/api/v2/list/goods/filter', limit: limit, offset: offset)
          items = Array(data.dig('data', 'listGoods') || data['data'] || data)
          break if items.empty?

          rows = items.filter_map { |r| build_product_price(r) }
          if rows.any?
            record_listing_price_changes(rows)
            RawWb::ProductPrice.where(account_id: @account.id,
                                      product_id: rows.map { |r| r[:product_id] })
                               .delete_all
            RawWb::ProductPrice.insert_all(rows)
          end
          total += rows.size
          break if items.size < limit
          offset += limit
          sleep 1
        end

        total
      end

      private

      def record_listing_price_changes(rows)
        existing = RawWb::ProductPrice
          .where(account_id: @account.id, product_id: rows.map { |row| row[:product_id] })
          .index_by(&:product_id)

        rows.each do |row|
          price = existing[row[:product_id]]
          next unless price

          product = RawWb::Product.find_by(id: row[:product_id])
          sku_product = product && wb_price_sku_product(product.nm_id)
          next unless sku_product

          Ec::ListingChangeRecorder.record(
            sku_product: sku_product,
            operation_type: "listing_pricing",
            before: wb_price_snapshot(price.attributes.symbolize_keys),
            after: wb_price_snapshot(row)
          )
        end
      end

      def wb_price_snapshot(values)
        values.slice(:price, :discount, :club_discount, :final_price, :is_in_quarantine)
      end

      def wb_price_sku_product(nm_id)
        store = @wb_price_store ||= Ec::Store.find_by(platform: 'wb', wb_raw_account_id: @account.id)
        return unless store

        Ec::SkuProduct.includes(:sku, :store).find_by(store: store, product_id: nm_id.to_s)
      end

      def build_product_price(r)
        nm_id = r['nmID'] || r['nmId']
        return nil if nm_id.blank?

        product = find_or_create_product(nm_id, r['vendorCode'])
        return nil unless product

        price    = Array(r['sizes']).first&.dig('price').to_f / 100
        discount = r['discount'].to_i

        {
          product_id:       product.id,
          account_id:       @account.id,
          price:            price,
          discount:         discount,
          club_discount:    r['clubDiscount'].to_i,
          final_price:      price * (100 - discount) / 100.0,
          is_in_quarantine: r['isInQuarantine'] || false,
        }
      end
    end
  end
end
