module Ec
  class PlatformProductAttributeOptionsQuery
    OZON_LARGE_DICTIONARY_ATTRIBUTE_IDS = [85, 4389, 22232].freeze
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 500

    def initialize(platform:, attribute_id:, account_id: nil, description_category_id: nil, type_id: nil,
      subject_id: nil, subject_wb_id: nil, query: nil, limit: DEFAULT_LIMIT)
      @platform = platform.to_s
      @attribute_id = attribute_id.to_i
      @account_id = account_id
      @description_category_id = description_category_id
      @type_id = type_id.to_i
      @subject_id = subject_id
      @subject_wb_id = subject_wb_id
      @query = query.to_s.strip
      @limit = [[limit.to_i, 1].max, MAX_LIMIT].min
    end

    def call
      case @platform
      when "ozon"
        ozon_options
      when "wb"
        wb_options
      else
        empty_result
      end
    end

    private

    def ozon_options
      return empty_result if @description_category_id.blank? || @attribute_id.zero?

      attribute = RawOzon::CategoryAttribute
        .where(
          description_category_id: @description_category_id,
          type_id: @type_id,
          attribute_id: @attribute_id
        )
        .order(:attribute_complex_id)
        .first

      options = if large_ozon_dictionary?
        search_ozon_dictionary_values
      else
        RawOzon::AttributeValue
          .where(
            description_category_id: @description_category_id,
            type_id: @type_id,
            attribute_id: @attribute_id
          )
          .then { |scope| filter_option_scope(scope, :value) }
          .order(:value)
          .limit(@limit)
          .map do |value|
            {
              id: value.dictionary_value_id,
              value: value.value,
              info: value.info,
              picture: value.picture
            }
          end
      end

      {
        platform: "ozon",
        attribute: ozon_attribute_payload(attribute),
        options: options,
        free_input: attribute.blank? || attribute.dictionary_id.to_i.zero?
      }
    end

    def wb_options
      subject = wb_subject
      return empty_result if subject.blank? || @attribute_id.zero?

      attribute = RawWb::Characteristic.find_by(subject_id: subject.id, wb_id: @attribute_id)
      dict_type = attribute&.dictionary_type
      options = []

      if dict_type.present?
        scope = RawWb::AttributeDict.where(dict_type: dict_type)
        scope = dict_type == "tnved" ? scope.where(scope_key: subject.wb_id.to_s) : scope.where(scope_key: "")
        options = filter_option_scope(scope, :name)
          .order(:name)
          .limit(@limit)
          .map { |value| { id: value.wb_id.presence || value.value_key, value: value.name, parent_name: value.parent_name } }
      end

      {
        platform: "wb",
        attribute: wb_attribute_payload(attribute),
        options: options,
        free_input: dict_type.blank?
      }
    end

    def wb_subject
      return RawWb::Subject.find_by(wb_id: @subject_wb_id) if @subject_wb_id.present?
      return if @subject_id.blank?

      RawWb::Subject.find_by(id: @subject_id)
    end

    def large_ozon_dictionary?
      OZON_LARGE_DICTIONARY_ATTRIBUTE_IDS.include?(@attribute_id)
    end

    def search_ozon_dictionary_values
      return [] if @query.length < 2 || @account_id.blank?

      account = RawOzon::SellerAccount.find_by(id: @account_id)
      return [] unless account

      response = RawOzon::OzonClient.new(account.client_id, account.api_key).post(
        "/v1/description-category/attribute/values/search",
        {
          attribute_id: @attribute_id,
          description_category_id: @description_category_id,
          type_id: @type_id,
          value: @query,
          limit: [@limit, 100].min
        }
      )
      Array(response["result"]).filter_map do |value|
        dictionary_value_id = value["id"] || value["dictionary_value_id"]
        next if dictionary_value_id.blank?

        {
          id: dictionary_value_id,
          value: value["value"],
          info: value["info"],
          picture: value["picture"]
        }
      end
    rescue RawOzon::OzonClient::ApiError, RawOzon::OzonClient::RetryableError
      []
    end

    def filter_option_scope(scope, column)
      return scope if @query.blank?

      quoted_column = scope.connection.quote_column_name(column)
      scope.where("#{quoted_column} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%")
    end

    def ozon_attribute_payload(attribute)
      return nil unless attribute

      {
        id: attribute.attribute_id,
        name: attribute.name,
        value_type: attribute.value_type,
        dictionary_id: attribute.dictionary_id,
        required: attribute.is_required,
        multiple: attribute.is_collection || attribute.max_value_count.to_i > 1,
        max_count: attribute.max_value_count,
        raw_json: attribute.raw_json
      }
    end

    def wb_attribute_payload(attribute)
      return nil unless attribute

      {
        id: attribute.wb_id,
        name: attribute.name,
        data_type: attribute.data_type,
        charc_type: attribute.charc_type,
        dictionary_type: attribute.dictionary_type,
        required: attribute.is_required,
        multiple: attribute.max_count.to_i > 1,
        max_count: attribute.max_count,
        unit_name: attribute.unit_name,
        raw_json: attribute.raw_json
      }
    end

    def empty_result
      { platform: @platform, attribute: nil, options: [], free_input: true }
    end
  end
end
