module RawWb
  module Syncs
    module Subjects
      # GET /content/v2/object/all — content-api (sub-categories / предметы)
      def sync_subjects
        offset         = 0
        total          = 0
        limit          = 1000
        category_cache = RawWb::Category.pluck(:wb_id, :id).to_h

        loop do
          data  = @client.get(:content, '/content/v2/object/all', limit: limit, offset: offset)
          items = Array(data['data'])
          break if items.empty?

          rows = items.filter_map do |r|
            wb_id = r['subjectID']
            next if wb_id.blank?
            {
              wb_id:       wb_id,
              name:        r['subjectName'],
              category_id: category_cache[r['parentID']],
              synced_at:   Time.current,
            }
          end
          RawWb::Subject.upsert_all(rows, unique_by: :wb_id, update_only: %i[name category_id synced_at]) if rows.any?
          total += rows.size
          break if items.size < limit
          offset += limit
          sleep 0.7
        end

        total
      end
    end
  end
end
