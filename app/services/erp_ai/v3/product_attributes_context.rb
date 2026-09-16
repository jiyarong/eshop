module ErpAI
  module V3
    class ProductAttributesContext
      OPTIONS_LIMIT = 100

      def self.call(sku:)
        new(sku: sku).call
      end

      def initialize(sku:, options_query: Ec::PlatformProductAttributeOptionsQuery)
        @sku = sku
        @options_query = options_query
      end

      def call
        {
          listings: sku.sku_products.active.ordered.includes(:store).map do |sku_product|
            listing_context(sku_product)
          end
        }
      end

      private

      attr_reader :sku, :options_query

      def listing_context(sku_product)
        base = {
          sku_product_id: sku_product.id,
          platform: sku_product.platform,
          store_id: sku_product.store_id,
          store_name: sku_product.store.store_name,
          product_id: sku_product.product_id,
          offer_id: sku_product.offer_id
        }

        case sku_product.platform
        when "ozon"
          base.merge(ozon_context(sku_product))
        when "wb"
          base.merge(wb_context(sku_product))
        else
          base.merge(source_found: false, category: {}, attributes: [])
        end
      end

      def ozon_context(sku_product)
        account_id = sku_product.store.ozon_raw_account_id
        product_id = sku_product.product_id.to_i
        product = RawOzon::Product.find_by(account_id: account_id, ozon_product_id: product_id)
        stored_attributes = RawOzon::ProductAttribute.find_by(
          account_id: account_id,
          ozon_product_id: product_id
        )

        {
          source_found: product.present?,
          attributes_synced: stored_attributes.present?,
          category: {
            description_category_id: product&.description_category_id,
            type_id: product&.type_id
          },
          attributes: ozon_attributes(
            stored_attributes,
            account_id: account_id,
            description_category_id: product&.description_category_id,
            type_id: product&.type_id
          )
        }
      end

      def ozon_attributes(stored_attributes, account_id:, description_category_id:, type_id:)
        current_attributes = Array(stored_attributes&.product_attributes) +
          Array(stored_attributes&.complex_attributes)

        flatten_ozon_attributes(current_attributes).filter_map do |attribute|
          attribute = attribute.with_indifferent_access
          attribute_id = attribute[:id].to_i
          next if attribute_id.zero?

          result = options_query.new(
            platform: "ozon",
            account_id: account_id,
            description_category_id: description_category_id,
            type_id: type_id,
            attribute_id: attribute_id,
            limit: OPTIONS_LIMIT
          ).call

          attribute_payload(attribute, result, platform: "ozon")
        end
      end

      def wb_context(sku_product)
        account_id = sku_product.store.wb_raw_account_id
        product = RawWb::Product
          .includes(:subject, :product_characteristics)
          .find_by(account_id: account_id, nm_id: sku_product.product_id.to_i)

        {
          source_found: product.present?,
          attributes_synced: product&.product_characteristics&.loaded? || false,
          category: {
            subject_id: product&.subject_id,
            subject_wb_id: product&.subject&.wb_id,
            subject_name: product&.subject_name || product&.subject&.name
          },
          attributes: wb_attributes(product)
        }
      end

      def wb_attributes(product)
        return [] unless product

        product.product_characteristics.sort_by { |attribute| [ attribute.charc_id.to_i, attribute.id ] }.map do |attribute|
          result = options_query.new(
            platform: "wb",
            subject_id: product.subject_id,
            attribute_id: attribute.charc_id,
            limit: OPTIONS_LIMIT
          ).call

          attribute_payload(
            { id: attribute.charc_id, name: attribute.charc_name, values: attribute.value },
            result,
            platform: "wb"
          )
        end
      end

      def attribute_payload(attribute, result, platform:)
        definition = result[:attribute]&.except(:raw_json)
        {
          id: attribute[:id].to_i,
          name: attribute[:name].presence || definition&.fetch(:name, nil),
          current_values: normalized_values(attribute[:values] || attribute[:value]),
          definition: definition,
          input_mode: input_mode(platform, attribute[:id], result),
          options: result[:options]
        }
      end

      def input_mode(platform, attribute_id, result)
        return "unknown" unless result[:attribute]
        return "free_input" if result[:free_input]
        if platform == "ozon" &&
            Ec::PlatformProductAttributeOptionsQuery::OZON_LARGE_DICTIONARY_ATTRIBUTE_IDS.include?(attribute_id.to_i)
          return "remote_search"
        end

        "dictionary"
      end

      def flatten_ozon_attributes(attributes)
        Array(attributes).flat_map do |attribute|
          next [] unless attribute.is_a?(Hash)

          nested = attribute["attributes"] || attribute[:attributes]
          [ attribute ] + (nested.is_a?(Array) ? flatten_ozon_attributes(nested) : [])
        end
      end

      def normalized_values(value)
        values = value.is_a?(Array) ? value : [ value ]
        values.compact.map do |item|
          if item.is_a?(Hash)
            item = item.with_indifferent_access
            {
              id: item[:dictionary_value_id] || item[:id],
              value: item[:value] || item[:name] || item.to_h
            }.compact
          else
            { value: item }
          end
        end
      end
    end
  end
end
