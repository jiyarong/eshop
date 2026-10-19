require "uri"

module Ec
  class OzonListingValidator
    MAX_OFFER_ID_LENGTH = 50
    MAX_TITLE_LENGTH = 200
    MAX_IMAGES = 30

    Result = Struct.new(:errors, :warnings, keyword_init: true) do
      def valid?
        errors.empty?
      end

      def invalid?
        !valid?
      end

      def to_h
        { errors: errors, warnings: warnings, valid: valid? }
      end
    end

    def initialize(payload = nil, account: nil, client: nil, **payload_keywords)
      payload = payload_keywords if payload.nil? && payload_keywords.present?
      @payload = normalize_payload(payload.to_h.deep_symbolize_keys)
      @account = account
      @client = client
    end

    def call
      errors = []
      warnings = []
      validate_identity(errors)
      validate_category(errors)
      validate_attributes(errors)
      validate_dimensions(errors)
      validate_price(errors)
      validate_images(errors)
      validate_quota(errors, warnings)
      Result.new(errors:, warnings:)
    end

    alias validate call

    def validate!
      result = call
      raise ArgumentError, result.errors.map { |error| error[:message] }.join("; ") unless result.valid?

      result
    end

    private

    attr_reader :payload, :account, :client

    def normalize_payload(value)
      value[:category] ||= {
        description_category_id: value[:description_category_id] || value[:category_id],
        type_id: value[:type_id]
      }.compact
      value[:dimensions] ||= {
        length: value[:length] || value[:depth],
        width: value[:width],
        height: value[:height],
        unit: value[:dimension_unit]
      }.compact
      value[:price] = { price: value[:price], old_price: value[:old_price], min_price: value[:min_price], currency_code: value[:currency_code] }.compact if value[:price].is_a?(Numeric) || value[:price].is_a?(String)
      value
    end

    def add_error(errors, field:, message:, attribute_id: nil, severity: "error", remediation: nil)
      errors << {
        field: field.to_s,
        attribute_id: attribute_id,
        severity: severity,
        message: message,
        remediation: remediation
      }.compact
    end

    def validate_identity(errors)
      offer_id = payload[:offer_id].to_s
      add_error(errors, field: :offer_id, message: "offer_id is required", remediation: "Provide a stable seller offer_id") if offer_id.blank?
      add_error(errors, field: :offer_id, message: "offer_id is too long", remediation: "Use at most #{MAX_OFFER_ID_LENGTH} characters") if offer_id.length > MAX_OFFER_ID_LENGTH

      title = payload[:name].to_s
      add_error(errors, field: :name, message: "title is required", remediation: "Provide a product title") if title.blank?
      add_error(errors, field: :name, message: "title is too long", remediation: "Use at most #{MAX_TITLE_LENGTH} characters") if title.length > MAX_TITLE_LENGTH

      currency = payload[:currency_code].presence || payload.dig(:price, :currency_code)
      add_error(errors, field: :currency_code, message: "currency_code must be RUB", remediation: "Use the store currency") unless currency.to_s.upcase == "RUB"
    end

    def validate_category(errors)
      category = payload[:category].to_h
      category_id = category[:description_category_id]
      type_id = category[:type_id]
      add_error(errors, field: :description_category_id, message: "description_category_id is required", remediation: "Select an enabled leaf category") if category_id.blank?
      add_error(errors, field: :type_id, message: "type_id is required", remediation: "Select a category type") if type_id.blank?
      return if category_id.blank? || type_id.blank? || account.blank?

      category_record = RawOzon::Category.where(account_id: account.id, category_id: category_id).first
      if category_record.nil?
        add_error(errors, field: :description_category_id, message: "category is not present in the local Ozon catalog", remediation: "Sync the Ozon category catalog")
      elsif category_record.disabled?
        add_error(errors, field: :description_category_id, message: "category is disabled", remediation: "Choose an enabled leaf category")
      elsif category_record.children.present? && Array(category_record.children).any?
        add_error(errors, field: :description_category_id, message: "category must be a leaf", remediation: "Choose a category without children")
      end
    end

    def validate_attributes(errors)
      return if account.blank? || payload.dig(:category, :description_category_id).blank?

      category_id = payload.dig(:category, :description_category_id)
      type_id = payload.dig(:category, :type_id)
      definitions = RawOzon::CategoryAttribute.where(
        description_category_id: category_id,
        type_id: type_id
      ).to_a
      provided = Array(payload[:attributes]) + Array(payload[:complex_attributes])
      provided_by_id = provided.filter_map do |attribute|
        next unless attribute.is_a?(Hash)

        [attribute[:id].to_i, attribute]
      end.to_h

      definitions.select(&:is_required?).each do |definition|
        attribute = provided_by_id[definition.attribute_id]
        values = Array(attribute && (attribute[:values] || attribute["values"]))
        if attribute.blank? || values.empty?
          add_error(
            errors,
            field: "attributes.#{definition.attribute_id}",
            attribute_id: definition.attribute_id,
            message: "required attribute is missing",
            remediation: "Provide a value for #{definition.name.presence || definition.attribute_id}"
          )
          next
        end
      end

      provided.each do |attribute|
        next unless attribute.is_a?(Hash)
        definition = definitions.find { |item| item.attribute_id.to_i == attribute[:id].to_i }
        next unless definition

        values = Array(attribute[:values])
        if definition.max_value_count.present? && values.length > definition.max_value_count
          add_error(errors, field: "attributes.#{definition.attribute_id}", attribute_id: definition.attribute_id,
            message: "too many values for attribute", remediation: "Provide at most #{definition.max_value_count} values")
        end
        validate_dictionary_values(errors, definition, values)
      end

      Array(payload[:complex_attributes]).each_with_index do |complex, index|
        next unless complex.is_a?(Hash)

        nested = complex[:attributes] || complex["attributes"]
        values = complex[:values] || complex["values"]
        next if nested.is_a?(Array) || (values.is_a?(Array) && values.present?)

        add_error(
          errors,
          field: "complex_attributes.#{index}",
          attribute_id: complex[:id] || complex["id"],
          message: "complex attribute has an invalid shape",
          remediation: "Provide nested attributes or values for the complex attribute"
        )
      end
    end

    def validate_dictionary_values(errors, definition, values)
      return if definition.dictionary_id.to_i.zero?

      ids = values.filter_map do |value|
        value = value.to_h.deep_symbolize_keys
        value[:dictionary_value_id].presence
      end
      if ids.length != values.length
        add_error(errors, field: "attributes.#{definition.attribute_id}", attribute_id: definition.attribute_id,
          message: "dictionary attribute requires dictionary_value_id", remediation: "Select an exact value from the Ozon dictionary")
        return
      end

      scope = RawOzon::AttributeValue.where(
        description_category_id: definition.description_category_id,
        type_id: definition.type_id,
        attribute_id: definition.attribute_id,
        dictionary_value_id: ids
      )
      missing = ids.map(&:to_i) - scope.pluck(:dictionary_value_id)
      return if missing.empty?

      add_error(errors, field: "attributes.#{definition.attribute_id}", attribute_id: definition.attribute_id,
        message: "dictionary value is not in the synced Ozon catalog", remediation: "Search and select an exact dictionary value")
    end

    def validate_dimensions(errors)
      dimensions = payload[:dimensions].to_h
      %i[length width height].each do |field|
        value = dimensions[field]
        add_error(errors, field: "dimensions.#{field}", message: "dimension must be greater than zero", remediation: "Provide a positive package dimension") unless value.to_d.positive?
      end
      add_error(errors, field: :weight, message: "weight must be greater than zero", remediation: "Provide a positive package weight") unless payload[:weight].to_d.positive?
    end

    def validate_price(errors)
      price = payload[:price].to_h
      current = price[:price].to_d
      old = price[:old_price]
      add_error(errors, field: "price.price", message: "price must be greater than zero", remediation: "Provide a positive seller price") unless current.positive?
      if old.present? && old.to_d.positive? && old.to_d < current
        add_error(errors, field: "price.old_price", message: "old_price must be greater than or equal to price", remediation: "Correct the price relationship")
      end
    end

    def validate_images(errors)
      images = Array(payload[:images]).compact_blank
      primary = payload[:primary_image].presence || images.first
      add_error(errors, field: :images, message: "at least one image is required", remediation: "Provide a public HTTPS image URL") if images.empty? && primary.blank?
      add_error(errors, field: :images, message: "too many images", remediation: "Keep at most #{MAX_IMAGES} images") if images.length > MAX_IMAGES
      urls = ([primary] + images).compact.uniq
      urls.each do |url|
        uri = URI.parse(url.to_s)
        unless uri.is_a?(URI::HTTPS) && uri.host.present?
          add_error(errors, field: :images, message: "image URL must be public HTTPS", remediation: "Use an externally reachable HTTPS URL")
          break
        end
      rescue URI::InvalidURIError
        add_error(errors, field: :images, message: "image URL is invalid", remediation: "Use a valid public HTTPS URL")
        break
      end
    end

    def validate_quota(errors, warnings)
      return unless client && client.respond_to?(:quota)

      response = client.quota
      limit = response.dig("result", "limit") || response.dig("result", "items_limit") || response["limit"]
      used = response.dig("result", "used") || response.dig("result", "items_used") || response["used"]
      return if limit.blank? || used.blank? || limit.to_i > used.to_i

      add_error(errors, field: :quota, message: "Ozon product quota is exhausted", remediation: "Wait for quota or reduce the submission")
    rescue StandardError => error
      warnings << { field: "quota", message: "quota could not be checked: #{error.message}" }
    end
  end
end
