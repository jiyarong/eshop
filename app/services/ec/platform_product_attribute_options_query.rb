module Ec
  class PlatformProductAttributeOptionsQuery
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 500

    def initialize(platform:, attribute_id:, account_id: nil, description_category_id: nil, type_id: nil,
      subject_id: nil, query: nil, limit: DEFAULT_LIMIT)
      @platform = platform.to_s
      @attribute_id = attribute_id.to_i
      @account_id = account_id
      @description_category_id = description_category_id
      @type_id = type_id.to_i
      @subject_id = subject_id
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
      return empty_result if @account_id.blank? || @description_category_id.blank? || @attribute_id.zero?

      attribute = RawOzon::CategoryAttribute
        .where(
          account_id: @account_id,
          description_category_id: @description_category_id,
          type_id: @type_id,
          attribute_id: @attribute_id
        )
        .order(:attribute_complex_id)
        .first

      options = RawOzon::AttributeValue
        .where(
          account_id: @account_id,
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
      return if @subject_id.blank?

      RawWb::Subject.find_by(id: @subject_id) || RawWb::Subject.find_by(wb_id: @subject_id)
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
