require "json"

module Ec
  class OzonListingDraftBuilder
    DEFAULT_CURRENCY = "RUB".freeze
    DEFAULT_DIMENSION_UNIT = "mm".freeze
    DEFAULT_WEIGHT_UNIT = "g".freeze

    def initialize(sku:, store:, account: nil, overrides: {})
      @sku = sku
      @store = store
      @account = account || store.raw_ozon_account
      if @store.platform.to_s != "ozon"
        raise ArgumentError, "store must be an Ozon store"
      end
      if account && @store.ozon_raw_account_id.present? && @store.ozon_raw_account_id.to_i != account.id.to_i
        raise ArgumentError, "store and Ozon account do not match"
      end
      @overrides = overrides.to_h.deep_symbolize_keys
    end

    def call
      existing_product = existing_raw_product
      existing_attributes = if existing_product && @account
        RawOzon::ProductAttribute.find_by(account_id: @account.id, ozon_product_id: existing_product.ozon_product_id)
      end
      dimension = @sku.dimension
      info = product_info
      existing_payload = existing_product&.raw_json.to_h.deep_symbolize_keys

      {
        sku_code: @sku.sku_code,
        store_id: @store.id,
        account_id: @account&.id,
        offer_id: override(:offer_id, existing_product&.offer_id.presence || @sku.sku_code),
        category: {
          description_category_id: override(:description_category_id, existing_product&.description_category_id || existing_payload[:description_category_id]),
          type_id: override(:type_id, existing_product&.type_id || existing_payload[:type_id])
        }.compact,
        name: override(:name, info[:name].presence || @sku.product_name_ru.presence || @sku.product_name),
        description: override(:description, info[:description].presence || @sku.product_info.to_s.presence),
        barcodes: override(:barcodes, info[:barcodes].presence || Array(existing_product&.barcodes).compact_blank),
        dimensions: build_dimensions(dimension, info, existing_payload),
        weight: override(:weight, info[:weight] || existing_payload[:weight] || weight_grams(dimension)),
        weight_unit: override(:weight_unit, info[:weight_unit] || existing_payload[:weight_unit] || DEFAULT_WEIGHT_UNIT),
        vat: override(:vat, info[:vat] || existing_payload[:vat]),
        currency_code: override(:currency_code, existing_product&.currency_code || info[:currency_code] || DEFAULT_CURRENCY),
        attributes: override(:attributes, Array(existing_attributes&.product_attributes || info[:attributes])).compact,
        complex_attributes: override(:complex_attributes, Array(existing_attributes&.complex_attributes || info[:complex_attributes])).compact,
        images: override(:images, image_urls(existing_product, existing_payload)),
        primary_image: override(:primary_image, primary_image(existing_product, existing_payload)),
        color_image: override(:color_image, image_url(existing_product&.color_image || existing_payload[:color_image])),
        price: build_price(existing_product, existing_payload, info),
        stock: @overrides[:stock] || info[:stock]
      }.compact
    end

    alias build call

    def import_item
      payload = call
      dimensions = payload.fetch(:dimensions, {})
      {
        offer_id: payload[:offer_id],
        name: payload[:name],
        description: payload[:description],
        category_id: payload.dig(:category, :description_category_id),
        type_id: payload.dig(:category, :type_id),
        barcode: Array(payload[:barcodes]).first,
        barcodes: Array(payload[:barcodes]),
        depth: dimensions[:depth],
        width: dimensions[:width],
        height: dimensions[:height],
        dimension_unit: dimensions[:unit] || DEFAULT_DIMENSION_UNIT,
        weight: payload[:weight],
        weight_unit: payload[:weight_unit],
        vat: payload[:vat],
        currency_code: payload[:currency_code],
        attributes: Array(payload[:attributes]),
        complex_attributes: Array(payload[:complex_attributes]),
        images: Array(payload[:images]),
        primary_image: payload[:primary_image],
        color_image: payload[:color_image],
        price: payload.dig(:price, :price),
        old_price: payload.dig(:price, :old_price),
        min_price: payload.dig(:price, :min_price)
      }.compact
    end

    private

    def override(key, fallback)
      @overrides.key?(key) ? @overrides[key] : fallback
    end

    def existing_raw_product
      return unless @account

      product_id = @store.sku_products.find_by(sku_code: @sku.sku_code)&.product_id
      scope = RawOzon::Product.where(account_id: @account.id)
      scope.find_by(ozon_product_id: product_id.to_i) if product_id.present? && product_id.to_i.positive?
    end

    def product_info
      value = @sku.product_info.to_s
      return {} if value.blank?

      parsed = JSON.parse(value)
      parsed.is_a?(Hash) ? parsed.deep_symbolize_keys : {}
    rescue JSON::ParserError
      { description: value }
    end

    def build_dimensions(dimension, info, existing_payload)
      source = @overrides[:dimensions] || info[:dimensions] || {}
      source = source.deep_symbolize_keys if source.respond_to?(:deep_symbolize_keys)
      {
        length: source[:length] || existing_payload[:depth] || dimension_mm(dimension, :length),
        width: source[:width] || existing_payload[:width] || dimension_mm(dimension, :width),
        height: source[:height] || existing_payload[:height] || dimension_mm(dimension, :height),
        unit: source[:unit] || existing_payload[:dimension_unit] || DEFAULT_DIMENSION_UNIT
      }.compact
    end

    def dimension_mm(dimension, side)
      value = dimension&.public_send("outer_#{side}_cm") || dimension&.public_send("inner_#{side}_cm")
      value.present? ? (value.to_d * 10).to_f : nil
    end

    def weight_grams(dimension)
      kg = dimension&.outer_box_weight_kg || dimension&.inner_box_weight_kg || @sku.weight_kg
      kg.present? ? (kg.to_d * 1000).to_f : nil
    end

    def build_price(existing_product, existing_payload, info)
      source = @overrides[:price] || info[:price] || {}
      source = source.deep_symbolize_keys if source.respond_to?(:deep_symbolize_keys)
      existing_price = existing_product&.product_price
      {
        price: source[:price] || existing_price&.price || existing_payload.dig(:price, :price),
        old_price: source[:old_price] || existing_price&.old_price || existing_payload.dig(:price, :old_price),
        min_price: source[:min_price] || existing_price&.min_price || existing_payload.dig(:price, :min_price),
        currency_code: source[:currency_code] || existing_price&.currency_code || existing_payload[:currency_code] || DEFAULT_CURRENCY
      }.compact
    end

    def image_urls(existing_product, existing_payload)
      source = existing_product&.images || existing_payload[:images]
      urls = Array(source).filter_map { |image| image_url(image) }
      return urls.uniq if urls.present?

      @sku.attachments.where(attach_type: :listing_image).filter_map do |attachment|
        next attachment.oss_path if attachment.oss_path.to_s.start_with?("https://")
        next unless attachment.file.attached?

        Ec::OzonAttachmentUrlResolver.new.call(attachment)
      end.uniq
    end

    def primary_image(existing_product, existing_payload)
      image_url(existing_product&.raw_json.to_h["primary_image"] || existing_payload[:primary_image]) || image_urls(existing_product, existing_payload).first
    end

    def image_url(image)
      case image
      when String then image.presence
      when Hash then image["url"] || image[:url] || image["default"] || image[:default] || image["original"] || image[:original]
      end
    end
  end
end
