module RawWb
  module Syncs
    module AdCampaignCount
      # GET /adv/v1/promotion/count — advert-api
      # Response: { "adverts": [{ "type": 9, "status": 9, "count": 2, "advert_list": [...] }] }
      def sync_ad_campaign_count
        data   = @client.get(:advert, '/adv/v1/promotion/count')
        groups = Array(data['adverts'])
        total  = groups.sum { |g| g['count'].to_i }
        log "  Ad campaigns total: #{total} (#{groups.size} groups)"
        total
      end
    end
  end
end
