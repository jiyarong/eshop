module RawWb
  module Syncs
    module PromotionsList
      # GET /api/v1/calendar/promotions — advert-api (promotion calendar)
      def sync_promotions_list
        data  = @client.get(:advert, '/api/v1/calendar/promotions',
                            startDateTime: @from.iso8601,
                            endDateTime:   (Date.current + 30).iso8601)
        items = Array(data.is_a?(Hash) ? data['promotions'] || data : data)
        return 0 if items.empty?

        rows = items.filter_map { |r| build_promotion(r) }
        RawWb::Promotion.upsert_all(rows, unique_by: :wb_promotion_id,
          update_only: %i[name period_start period_end discount synced_at]) if rows.any?
        rows.size
      end

      private

      def build_promotion(r)
        promo_id = r['id'] || r['promotionId']
        return nil if promo_id.blank?
        {
          account_id:      @account.id,
          wb_promotion_id: promo_id,
          name:            r['name'],
          period_start:    r['startDateTime'] || r['dateStart'],
          period_end:      r['endDateTime'] || r['dateEnd'],
          discount:        r['discount'],
          synced_at:       Time.current,
        }
      end
    end
  end
end
