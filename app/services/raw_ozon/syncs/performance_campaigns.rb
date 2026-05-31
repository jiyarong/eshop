module RawOzon
  module Syncs
    module PerformanceCampaigns
      # GET /api/client/campaign — 同步所有活动及其关联 SKU
      def sync_performance_campaigns
        resp  = @perf_client.get('/api/client/campaign')
        items = Array(resp['list'])
        return 0 if items.empty?

        synced_at = Time.current

        rows = items.map do |c|
          {
            account_id:      @account.id,
            campaign_id:     c['id'],
            title:           c['title'],
            state:           c['state'],
            adv_object_type: c['advObjectType'],
            payment_type:    c['PaymentType'],
            placement:       Array(c['placement']),
            from_date:       c['fromDate'].presence,
            to_date:         c['toDate'].presence,
            daily_budget:    c['dailyBudget'].to_d,
            weekly_budget:   c['weeklyBudget'].to_d,
            raw_json:        c,
            synced_at:       synced_at,
          }
        end

        RawOzon::PerformanceCampaign.upsert_all(
          rows,
          unique_by: :idx_ozon_perf_campaigns_unique,
          update_only: %i[title state adv_object_type payment_type placement
                          from_date to_date daily_budget weekly_budget raw_json synced_at]
        )

        items.size
      end
    end
  end
end
