module RawOzon
  module Syncs
    module CategoryAttributes
      ATTRIBUTE_VALUES_PREFETCH_LIMIT = 500
      LARGE_DICTIONARY_ATTRIBUTE_IDS = [85, 4389, 22232].freeze

      # POST /v1/description-category/attribute + /v1/description-category/attribute/values
      # Syncs the shared catalog for categories present in this account's product catalog.
      def sync_category_attributes(force: false, pairs: nil)
        pairs ||= ozon_category_type_pairs
        return empty_sync_count if pairs.empty?

        total = empty_sync_count
        pairs.each do |description_category_id, type_id|
          next if !force && category_attribute_catalog_fresh?(description_category_id, type_id)

          attributes = fetch_ozon_category_attributes(description_category_id, type_id)
          synced_at = Time.current
          attribute_rows = attributes.map do |attribute|
            build_ozon_category_attribute(attribute, description_category_id, type_id, nil)
          end
          merge_sync_count!(total, upsert_ozon_category_attributes(attribute_rows)) if attribute_rows.any?

          complete = true
          attributes.each do |attribute|
            next if LARGE_DICTIONARY_ATTRIBUTE_IDS.include?(attribute["id"].to_i)
            next unless attribute["dictionary_id"].to_i.positive?

            value_rows, values_complete = fetch_ozon_attribute_value_rows(
              attribute, description_category_id, type_id, synced_at
            )
            complete &&= values_complete
            if values_complete
              merge_sync_count!(total, replace_ozon_attribute_values(
                value_rows, description_category_id, type_id, attribute["id"]
              ))
            end
          end
          mark_category_attribute_catalog_synced(description_category_id, type_id, synced_at) if complete
        end

        total
      end

      private

      def ozon_category_type_pairs
        RawOzon::Product
          .where(account_id: @account.id)
          .where.not(description_category_id: nil)
          .distinct
          .pluck(:description_category_id, :type_id)
          .map { |category_id, type_id| [category_id.to_i, type_id.to_i] }
          .uniq
      end

      def category_attribute_catalog_fresh?(description_category_id, type_id)
        scope = RawOzon::CategoryAttribute
          .where(description_category_id: description_category_id, type_id: type_id)
        scope.exists? && !scope.where(synced_at: nil).exists? &&
          scope.minimum(:synced_at) >= 7.days.ago
      end

      def fetch_ozon_category_attributes(description_category_id, type_id)
        body = { description_category_id: description_category_id, language: "RU" }
        body[:type_id] = type_id if type_id.positive?

        response = @client.post("/v1/description-category/attribute", body)
        Array(response["result"])
      end

      def fetch_ozon_attribute_value_rows(attribute, description_category_id, type_id, synced_at)
        attribute_id = attribute["id"].to_i
        body = {
          description_category_id: description_category_id,
          attribute_id: attribute_id,
          language: "RU",
          limit: ATTRIBUTE_VALUES_PREFETCH_LIMIT,
          last_value_id: 0
        }
        body[:type_id] = type_id if type_id.positive?

        rows = []
        last_value_id = 0
        loop do
          body[:last_value_id] = last_value_id
          response = @client.post("/v1/description-category/attribute/values", body)
          values = Array(response["result"])
          rows.concat(values.filter_map do |value|
            build_ozon_attribute_value(value, description_category_id, type_id, attribute_id, synced_at)
          end)
          unless response["has_next"] && values.any?
            return [rows, true]
          end

          next_value_id = values.filter_map { |value| ozon_dictionary_value_id(value).to_i }.max
          return [[], false] if next_value_id.blank? || next_value_id <= last_value_id

          last_value_id = next_value_id
          sleep 0.2
        end
      rescue OzonClient::ApiError, OzonClient::RetryableError => error
        log "Could not load Ozon attribute values for category #{description_category_id}, attribute #{attribute_id}: #{error.message}", level: :warn
        [[], false]
      end

      def build_ozon_category_attribute(attribute, description_category_id, type_id, synced_at)
        {
          description_category_id: description_category_id,
          type_id: type_id.to_i,
          attribute_id: attribute["id"].to_i,
          attribute_complex_id: ozon_attribute_complex_id(attribute),
          name: attribute["name"],
          description: attribute["description"],
          value_type: attribute["type"],
          group_id: attribute["group_id"],
          group_name: attribute["group_name"],
          dictionary_id: attribute["dictionary_id"].to_i,
          is_required: truthy?(attribute["is_required"]),
          is_collection: truthy?(attribute["is_collection"]),
          is_aspect: truthy?(attribute["is_aspect"]),
          category_dependent: truthy?(attribute["category_dependent"]),
          max_value_count: attribute["max_value_count"],
          complex_is_collection: truthy?(attribute["complex_is_collection"]),
          raw_json: attribute,
          synced_at: synced_at
        }
      end

      def build_ozon_attribute_value(value, description_category_id, type_id, attribute_id, synced_at)
        dictionary_value_id = ozon_dictionary_value_id(value)
        return if dictionary_value_id.blank?

        {
          description_category_id: description_category_id,
          type_id: type_id.to_i,
          attribute_id: attribute_id,
          dictionary_value_id: dictionary_value_id,
          value: value["value"],
          info: value["info"],
          picture: value["picture"],
          raw_json: value,
          synced_at: synced_at
        }
      end

      def ozon_attribute_complex_id(attribute)
        (attribute["attribute_complex_id"] || attribute["complex_id"]).to_i
      end

      def ozon_dictionary_value_id(value)
        value["dictionary_value_id"] || value["id"] || value["value_id"]
      end

      def upsert_ozon_category_attributes(rows)
        result = scoped_upsert_count_result(
          rows,
          model: RawOzon::CategoryAttribute,
          unique_keys: %i[description_category_id type_id attribute_id attribute_complex_id]
        )
        RawOzon::CategoryAttribute.upsert_all(rows, unique_by: "idx_raw_ozon_cat_attrs_unique")
        result
      end

      def replace_ozon_attribute_values(rows, description_category_id, type_id, attribute_id)
        result = scoped_upsert_count_result(
          rows,
          model: RawOzon::AttributeValue,
          unique_keys: %i[description_category_id type_id attribute_id dictionary_value_id]
        )
        RawOzon::AttributeValue.where(
          description_category_id: description_category_id,
          type_id: type_id.to_i,
          attribute_id: attribute_id
        ).delete_all
        RawOzon::AttributeValue.upsert_all(rows, unique_by: "idx_raw_ozon_attr_values_unique") if rows.any?
        result
      end

      def mark_category_attribute_catalog_synced(description_category_id, type_id, synced_at)
        RawOzon::CategoryAttribute.where(
          description_category_id: description_category_id,
          type_id: type_id.to_i,
        ).update_all(synced_at: synced_at)
      end

      def scoped_upsert_count_result(rows, model:, unique_keys:)
        existing = rows.map { |row| unique_keys.map { |key| row.fetch(key) } }.uniq.count do |values|
          model.exists?(unique_keys.zip(values).to_h)
        end

        {
          ok: rows.size,
          fetched: rows.size,
          created: rows.size - existing,
          updated: existing
        }
      end

      def truthy?(value)
        value == true || value.to_s == "true"
      end
    end
  end
end
