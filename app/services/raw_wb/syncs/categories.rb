module RawWb
  module Syncs
    module Categories
      # GET /content/v2/object/parent/all — content-api
      def sync_categories
        data = @client.get(:content, '/content/v2/object/parent/all')
        rows = Array(data['data']).filter_map do |r|
          { wb_id: r['id'], name: r['name'], synced_at: Time.current }
        end
        return 0 if rows.empty?

        RawWb::Category.upsert_all(rows, unique_by: :wb_id, update_only: %i[name synced_at])
        Ec::CategoryWbImporter.import_categories(rows)
        Ec::CategoryTranslationSync.translate_pending_for_source("wb")
        rows.size
      end
    end
  end
end
