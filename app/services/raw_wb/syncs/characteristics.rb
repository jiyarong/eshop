module RawWb
  module Syncs
    module Characteristics
      # GET /content/v2/object/charcs/{subjectId}
      def sync_characteristics
        total = empty_sync_count

        RawWb::Subject.find_each do |subject|
          data = @client.get(:content, "/content/v2/object/charcs/#{subject.wb_id}")
          items = Array(data["data"])
          synced_at = Time.current
          rows = items.filter_map { |item| build_wb_characteristic(subject, item, synced_at) }
          next if rows.empty?

          merge_sync_count!(
            total,
            upsert_count_result(rows, model: RawWb::Characteristic, unique_key: %i[subject_id wb_id])
          )
          RawWb::Characteristic.upsert_all(rows, unique_by: "idx_raw_wb_characteristics_subject_charc")
          sleep 0.5
        end

        total
      end

      private

      def build_wb_characteristic(subject, item, synced_at)
        charc_id = item["charcID"] || item["charcId"] || item["id"]
        name = item["name"]
        return if charc_id.blank? || name.blank?

        {
          subject_id: subject.id,
          wb_id: charc_id,
          name: name,
          data_type: item["type"] || item["dataType"],
          charc_type: item["charcType"],
          unit_name: item["unitName"],
          max_count: item["maxCount"],
          is_required: truthy?(item["required"]),
          is_popular: truthy?(item["popular"]),
          has_filter: truthy?(item["isFilter"]) || truthy?(item["filter"]),
          dictionary_type: wb_dictionary_type_for(item),
          raw_json: item,
          synced_at: synced_at
        }
      end

      def wb_dictionary_type_for(item)
        name = item["name"].to_s.downcase
        return "color" if name.include?("цвет")
        return "kind" if name == "пол" || name.include?("пол ")
        return "country" if name.include?("страна")
        return "season" if name.include?("сезон")
        return "vat" if name.include?("ндс")
        return "tnved" if name.include?("тнвэд") || name.include?("тн вэд")

        nil
      end

      def truthy?(value)
        value == true || value.to_s == "true"
      end
    end
  end
end
