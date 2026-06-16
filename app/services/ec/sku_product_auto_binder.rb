module Ec
  class SkuProductAutoBinder
    Result = Data.define(:created_count, :skipped_count)

    def self.call
      new.call
    end

    def call
      created_count = 0
      skipped_count = 0

      Ec::Store.active.find_each do |store|
        products_for(store).find_each do |product|
          attributes = attributes_for(store, product)
          next if attributes.blank?

          if Ec::SkuProduct.exists?(store: store, product_id: attributes.fetch(:product_id))
            skipped_count += 1
            next
          end

          Ec::SkuProduct.create!(attributes)
          created_count += 1
        end
      end

      Result.new(created_count:, skipped_count:)
    end

    private

    def products_for(store)
      case store.platform
      when "ozon"
        return RawOzon::Product.none if store.ozon_raw_account_id.blank?

        RawOzon::Product.where(account_id: store.ozon_raw_account_id)
      when "wb"
        return RawWb::Product.none if store.wb_raw_account_id.blank?

        RawWb::Product.where(account_id: store.wb_raw_account_id)
      else
        Ec::SkuProduct.none
      end
    end

    def attributes_for(store, product)
      case store.platform
      when "ozon"
        sku_code = product.offer_id.to_s.upcase
        return unless Ec::Sku.exists?(sku_code: sku_code)

        {
          sku_code: sku_code,
          store: store,
          product_id: product.ozon_product_id.to_s,
          offer_id: product.offer_id,
          platform_sku_id: product.raw_json&.dig("sku").to_s.presence,
          product_name: product.name
        }
      when "wb"
        sku_code = product.vendor_code.to_s.upcase
        return unless Ec::Sku.exists?(sku_code: sku_code)

        {
          sku_code: sku_code,
          store: store,
          product_id: product.nm_id.to_s,
          offer_id: product.vendor_code,
          product_name: product.title
        }
      end
    end
  end
end
