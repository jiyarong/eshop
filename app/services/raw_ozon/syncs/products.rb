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
          record_product_changes(info_items)
          RawOzon::Product.upsert_all(rows, unique_by: [:account_id, :ozon_product_id]) if rows.any?
          total   += rows.size
          last_id  = list_resp.dig('result', 'last_id').to_s
          break if last_id.empty? || items.size < 100
          sleep 0.5
        end

        total
      end

      # POST /v4/product/info/attributes (batch by locally synced products)
      def sync_product_attributes
        products = RawOzon::Product.where(account_id: @account.id).select(:ozon_product_id)
        return empty_sync_count if products.none?

        synced_at = Time.current
        total = empty_sync_count

        products.in_batches(of: 100) do |relation|
          product_ids = relation.pluck(:ozon_product_id)
          next if product_ids.empty?

          resp = @client.post(
            '/v4/product/info/attributes',
            { filter: { product_id: product_ids, visibility: 'ALL' }, limit: 100, last_id: '' }
          )
          items = Array(resp['result'])
          enrich_product_attribute_names(items)
          rows = items.map { |p| build_product_attribute(p, synced_at) }
          record_attribute_changes(items)
          merge_sync_count!(
            total,
            rows.any? ? upsert_product_attributes(rows) : empty_sync_count
          )
        end

        total
      end

      private

      def enrich_product_attribute_names(items)
        items.each do |item|
          names = product_attribute_names(
            description_category_id: item['description_category_id'],
            type_id: item['type_id']
          )
          next if names.empty?

          item['attributes'] = attributes_with_names(item['attributes'], names)
          item['complex_attributes'] = attributes_with_names(item['complex_attributes'], names)
        end
      end

      def product_attribute_names(description_category_id:, type_id:)
        return {} if description_category_id.blank?

        key = [description_category_id, type_id]
        @product_attribute_names ||= {}
        @product_attribute_names[key] ||= begin
          body = { description_category_id: description_category_id, language: 'RU' }
          body[:type_id] = type_id if type_id.present?
          response = @client.post('/v1/description-category/attribute', body)
          Array(response['result']).to_h { |attribute| [attribute['id'].to_s, attribute['name']] }
        rescue OzonClient::ApiError, OzonClient::RetryableError => error
          log "Could not load product attribute names for category #{description_category_id}: #{error.message}", level: :warn
          {}
        end
      end

      def attributes_with_names(attributes, names)
        Array(attributes).map do |attribute|
          next attribute unless attribute.is_a?(Hash)

          attribute['name'] = names[attribute['id'].to_s] if attribute['name'].blank?
          attribute['attributes'] = attributes_with_names(attribute['attributes'], names) if attribute['attributes'].is_a?(Array)
          attribute
        end
      end

      def record_product_changes(items)
        existing = RawOzon::Product
          .where(account_id: @account.id, ozon_product_id: items.filter_map { |item| item['id'] })
          .index_by(&:ozon_product_id)

        items.each do |item|
          product = existing[item['id']]
          next unless product

          sku_product = ozon_sku_product(product.ozon_product_id)
          next unless sku_product

          Ec::ListingChangeRecorder.record(
            sku_product: sku_product,
            operation_type: "listing_content",
            before: ozon_content_snapshot(product.attributes.symbolize_keys),
            after: ozon_content_snapshot(build_product(item, Time.current))
          )
        end
      end

      def record_attribute_changes(items)
        existing = RawOzon::ProductAttribute
          .where(account_id: @account.id, ozon_product_id: items.map { |item| item['id'] || item['product_id'] })
          .index_by(&:ozon_product_id)

        items.each do |item|
          product_id = item['id'] || item['product_id']
          attribute = existing[product_id]
          next unless attribute

          sku_product = ozon_sku_product(product_id)
          next unless sku_product

          old_attributes = Array(attribute.product_attributes)
          new_attributes = Array(item['attributes'])
          Ec::ListingChangeRecorder.record(
            sku_product: sku_product,
            operation_type: "listing_content",
            before: { brand: ozon_brand(old_attributes) },
            after: { brand: ozon_brand(new_attributes) }
          )
          Ec::ListingChangeRecorder.record(
            sku_product: sku_product,
            operation_type: "listing_specification",
            before: ozon_specification_snapshot(
              attributes: old_attributes,
              complex_attributes: attribute.complex_attributes,
              barcode: attribute.barcode,
              raw_json: attribute.raw_json
            ),
            after: ozon_specification_snapshot(
              attributes: new_attributes,
              complex_attributes: item['complex_attributes'],
              barcode: item['barcode'],
              raw_json: item
            )
          )
        end
      end

      def ozon_content_snapshot(values)
        {
          title: values[:name],
          category_id: values[:description_category_id],
          type_id: values[:type_id],
          primary_image: ozon_image_url(values[:primary_image] || values.dig(:raw_json, 'primary_image')),
          images: ozon_image_urls(values[:images]),
          images360: ozon_image_urls(values[:images360]),
          color_image: ozon_image_url(values[:color_image])
        }
      end

      def ozon_image_urls(images)
        Array(images).filter_map { |image| ozon_image_url(image) }
      end

      def ozon_image_url(image)
        return image if image.is_a?(String)
        return unless image.is_a?(Hash)

        image['default'] || image[:default] || image['original'] || image[:original] || image['url'] || image[:url]
      end

      def ozon_brand(attributes)
        attribute = Array(attributes).find do |item|
          item['id'].to_i == 85 || item[:id].to_i == 85 || %w[brand бренд].include?((item['name'] || item[:name]).to_s.downcase)
        end
        Array(attribute && (attribute['values'] || attribute[:values])).filter_map do |value|
          value.is_a?(Hash) ? value['value'] || value[:value] : value
        end
      end

      def ozon_specification_snapshot(attributes:, complex_attributes:, barcode:, raw_json:)
        payload = raw_json.to_h
        barcodes = Array(payload['barcodes'] || payload[:barcodes])
        barcodes = Array(barcode) if barcodes.empty?
        filtered_attributes = Array(attributes).reject { |item| item['id'].to_i == 85 || item[:id].to_i == 85 }
        {
          barcodes: barcodes,
          width: payload['width'] || payload[:width],
          height: payload['height'] || payload[:height],
          depth: payload['depth'] || payload[:depth],
          dimension_unit: payload['dimension_unit'] || payload[:dimension_unit],
          weight: payload['weight'] || payload[:weight],
          weight_unit: payload['weight_unit'] || payload[:weight_unit],
          attributes: ozon_attribute_map(filtered_attributes),
          complex_attributes: normalize_ozon_complex_attributes(complex_attributes)
        }
      end

      def ozon_attribute_map(attributes)
        Array(attributes).sort_by { |item| (item['id'] || item[:id]).to_i }.to_h do |item|
          id = item['id'] || item[:id]
          [id.to_s, {
            name: item['name'] || item[:name],
            values: item['values'] || item[:values] || []
          }]
        end
      end

      def normalize_ozon_complex_attributes(attributes)
        Array(attributes).sort_by { |item| (item['id'] || item[:id]).to_i }
      end

      def ozon_sku_product(product_id)
        store = ozon_store
        return unless store

        Ec::SkuProduct.includes(:sku, :store).find_by(store: store, product_id: product_id.to_s)
      end

      def ozon_store
        @ozon_store ||= Ec::Store.find_by(platform: 'ozon', ozon_raw_account_id: @account.id)
      end

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

      def build_product_attribute(p, synced_at)
        {
          account_id:           @account.id,
          ozon_product_id:      p['id'] || p['product_id'],
          offer_id:             p['offer_id'],
          product_attributes:   Array(p['attributes']),
          complex_attributes:   Array(p['complex_attributes']),
          barcode:              p['barcode'],
          raw_json:             p,
          synced_at:            synced_at,
        }
      end

      def upsert_product_attributes(rows)
        result = upsert_count_result(rows, model: RawOzon::ProductAttribute, unique_key: :ozon_product_id)
        RawOzon::ProductAttribute.upsert_all(rows, unique_by: [:account_id, :ozon_product_id])
        result
      end
    end
  end
end
