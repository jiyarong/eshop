module RawWb
  module Syncs
    module AdCampaigns
      # GET /adv/v1/promotion/count   — campaign list (id + type + status)
      # GET /api/advert/v2/adverts   — campaign details (settings.name + nm_settings[].nm_id/bids_kopecks)
      def sync_ad_campaigns
        data   = @client.get(:advert, '/adv/v1/promotion/count')
        groups = Array(data['adverts'])
        return 0 if groups.empty?

        rows = groups.flat_map do |g|
          Array(g['advert_list']).filter_map do |a|
            advert_id = a['advertId']
            next if advert_id.blank?
            {
              account_id:    @account.id,
              wb_advert_id:  advert_id,
              name:          nil,
              campaign_type: g['type'],
              status:        g['status'],
              synced_at:     Time.current,
            }
          end
        end
        return 0 if rows.empty?

        RawWb::AdCampaign.upsert_all(rows, unique_by: :wb_advert_id,
          update_only: %i[status campaign_type synced_at])

        # Phase 2: GET /api/advert/v2/adverts — returns all campaigns with nm_settings
        # (id param is ignored by the API; always returns full list)
        details     = @client.get(:advert, '/api/advert/v2/adverts')
        detail_list = Array(details.is_a?(Hash) ? details['adverts'] : details)

        campaign_lookup = RawWb::AdCampaign.where(account_id: @account.id).index_by(&:wb_advert_id)

        detail_list.each do |d|
          advert_id = d['id']
          next if advert_id.blank?

          campaign = campaign_lookup[advert_id]
          next unless campaign

          name = d.dig('settings', 'name')
          campaign.update_columns(name: name) if name.present?

          nm_ids = Array(d['nm_settings']).filter_map { |s| s['nm_id'] }
          next if nm_ids.empty?

          product_rows = Array(d['nm_settings']).filter_map do |s|
            next unless s['nm_id']
            {
              campaign_id: campaign.id,
              nm_id:       s['nm_id'],
              bid:         s.dig('bids_kopecks', 'search').to_f / 100,
            }
          end
          RawWb::AdCampaignProduct.where(campaign_id: campaign.id).delete_all
          RawWb::AdCampaignProduct.insert_all(product_rows)
        end

        rows.size
      end
    end
  end
end
