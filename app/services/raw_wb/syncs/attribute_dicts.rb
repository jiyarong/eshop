module RawWb
  module Syncs
    module AttributeDicts
      GLOBAL_DICTIONARY_ENDPOINTS = {
        "color" => "/content/v2/directory/colors",
        "kind" => "/content/v2/directory/kinds",
        "country" => "/content/v2/directory/countries",
        "season" => "/content/v2/directory/seasons",
        "vat" => "/content/v2/directory/vat"
      }.freeze

      # GET /content/v2/directory/*
      def sync_attribute_dicts
        total = empty_sync_count
        synced_at = Time.current

        GLOBAL_DICTIONARY_ENDPOINTS.each do |dict_type, path|
          rows = wb_dictionary_rows(dict_type, @client.get(:content, path), synced_at: synced_at)
          merge_sync_count!(total, upsert_wb_attribute_dicts(rows)) if rows.any?
          sleep 0.5
        rescue WbClient::ApiError, WbClient::RetryableError => error
          log "Could not load WB #{dict_type} dictionary: #{error.message}", level: :warn
        end

        wb_attribute_subject_scope.find_each do |subject|
          rows = wb_dictionary_rows(
            "tnved",
            @client.get(:content, "/content/v2/directory/tnved", subjectID: subject.wb_id),
            subject: subject,
            synced_at: synced_at
          )
          merge_sync_count!(total, upsert_wb_attribute_dicts(rows)) if rows.any?
          sleep 0.5
        rescue WbClient::ApiError, WbClient::RetryableError => error
          log "Could not load WB TNVED dictionary for subject #{subject.wb_id}: #{error.message}", level: :warn
        end

        total
      end

      private

      def wb_attribute_subject_scope
        RawWb::Subject.where(
          id: RawWb::Product.where(account_id: @account.id).where.not(subject_id: nil).select(:subject_id).distinct
        )
      end

      def wb_dictionary_rows(dict_type, response, subject: nil, synced_at:)
        wb_dictionary_items(response).filter_map do |item|
          item = { "name" => item } unless item.is_a?(Hash)
          name = wb_dictionary_name(item)
          next if name.blank?

          wb_id = wb_dictionary_id(item)
          value_key = wb_id.presence || name.downcase
          {
            dict_type: dict_type,
            subject_id: subject&.id,
            scope_key: subject ? subject.wb_id.to_s : "",
            value_key: value_key.to_s,
            wb_id: wb_id,
            name: name,
            parent_name: item["parentName"] || item["parent_name"],
            raw_json: item,
            synced_at: synced_at
          }
        end
      end

      def wb_dictionary_items(response)
        case response
        when Array
          response
        when Hash
          data = response["data"]
          data.is_a?(Hash) ? Array(data["data"] || data["items"] || data["content"]) : Array(data)
        else
          []
        end
      end

      def wb_dictionary_id(item)
        item["id"] || item["ID"] || item["wbID"] || item["tnved"] || item["code"]
      end

      def wb_dictionary_name(item)
        item["name"] || item["fullName"] || item["value"] || item["tnvedName"] || item["code"]
      end

      def upsert_wb_attribute_dicts(rows)
        result = upsert_count_result(rows, model: RawWb::AttributeDict, unique_key: %i[dict_type scope_key value_key])
        RawWb::AttributeDict.upsert_all(rows, unique_by: "idx_raw_wb_attribute_dicts_unique")
        result
      end
    end
  end
end
