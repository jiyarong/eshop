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
