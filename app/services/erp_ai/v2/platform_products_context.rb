module ErpAI
  module V2
    class PlatformProductsContext
      def initialize(sku_products:)
        @sku_products = sku_products.to_a.sort_by(&:id)
      end

      def call
        wb_products = load_wb_products
        ozon_products = load_ozon_products
        ozon_prices = load_ozon_prices

        sku_products.map do |sku_product|
          product = product_for(sku_product, wb_products, ozon_products)

          {
            store_id: sku_product.store_id,
            platform: sku_product.platform,
            product_id: sku_product.product_id,
            offer_id: sku_product.offer_id,
            product_info: product_info(sku_product.platform, product),
            price_info: price_info(sku_product.platform, price_for(sku_product, product, ozon_prices))
          }
        end
      end

      private

      attr_reader :sku_products

      def load_wb_products
        keys = sku_products.filter_map do |binding|
          next unless binding.platform == "wb" && binding.store&.wb_raw_account_id && binding.product_id

          [binding.store.wb_raw_account_id, binding.product_id.to_i]
        end
        return {} if keys.empty?

        RawWb::Product
          .includes(:product_price)
          .where(account_id: keys.map(&:first).uniq, nm_id: keys.map(&:last).uniq)
          .index_by { |product| [product.account_id, product.nm_id] }
      end

      def load_ozon_products
        keys = sku_products.filter_map do |binding|
          next unless binding.platform == "ozon" && binding.store&.ozon_raw_account_id && binding.product_id

          [binding.store.ozon_raw_account_id, binding.product_id.to_i]
        end
        return {} if keys.empty?

        RawOzon::Product
          .where(account_id: keys.map(&:first).uniq, ozon_product_id: keys.map(&:last).uniq)
          .index_by { |product| [product.account_id, product.ozon_product_id] }
      end

      def load_ozon_prices
        keys = sku_products.filter_map do |binding|
          next unless binding.platform == "ozon" && binding.store&.ozon_raw_account_id && binding.product_id

          [binding.store.ozon_raw_account_id, binding.product_id.to_i]
        end
        return {} if keys.empty?

        RawOzon::ProductPrice
          .where(account_id: keys.map(&:first).uniq, ozon_product_id: keys.map(&:last).uniq)
          .index_by { |price| [price.account_id, price.ozon_product_id] }
      end

      def product_for(binding, wb_products, ozon_products)
        case binding.platform
        when "wb"
          wb_products[[binding.store&.wb_raw_account_id, binding.product_id.to_i]]
        when "ozon"
          ozon_products[[binding.store&.ozon_raw_account_id, binding.product_id.to_i]]
        end
      end

      def price_for(binding, product, ozon_prices)
        return unless product
        return product.product_price if binding.platform == "wb"

        ozon_prices[[binding.store&.ozon_raw_account_id, binding.product_id.to_i]]
      end

      def product_info(platform, product)
        return unless product

        if platform == "wb"
          product.attributes.slice(
            "nm_id", "vendor_code", "title", "brand", "subject_id", "subject_name",
            "wb_category", "description", "is_in_trash", "synced_at"
          )
        else
          product.attributes.slice(
            "ozon_product_id", "offer_id", "name", "description_category_id", "type_id",
            "currency_code", "barcodes", "is_archived", "is_autoarchived",
            "has_discounted_fbo_item", "discounted_fbo_stocks", "created_at", "synced_at"
          )
        end
      end

      def price_info(platform, price)
        return unless price

        if platform == "wb"
          price.attributes.slice(
            "price", "discount", "club_discount", "final_price", "is_in_quarantine", "updated_at"
          )
        else
          price.attributes.slice(
            "price", "old_price", "marketing_price", "min_price", "buybox_price",
            "discount_percent", "is_in_discount", "currency_code", "acquiring",
            "volume_weight", "synced_at"
          )
        end
      end
    end
  end
end
