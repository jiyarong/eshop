module RawOzon
  module Syncs
    module Promotions
      # GET /v1/actions
      def sync_promotions
        resp  = @client.get('/v1/actions')
        items = Array(resp['result'])
        return 0 if items.empty?

        synced_at = Time.current
        rows = items.map do |a|
          {
            account_id:                  @account.id,
            action_id:                   a['id'],
            title:                       a['title'],
            action_type:                 a['action_type'],
            description:                 a['description'],
            is_participating:            a['is_participating'] || false,
            participating_products_count: a['participating_products_count'].to_i,
            products_count:              a['products_count'].to_i,
            raw_json:                    a,
            date_start:                  a['date_start'],
            date_end:                    a['date_end'],
            freeze_date:                 a['freeze_date'],
            synced_at:                   synced_at,
          }
        end

        RawOzon::Promotion.upsert_all(rows, unique_by: [:account_id, :action_id],
                                      update_only: %i[is_participating participating_products_count synced_at])
        rows.size
      end
    end
  end
end
