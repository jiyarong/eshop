module RawWb
  module Syncs
    module AdStats
      # GET /adv/v3/fullstats — advert-api
      # Params: ids (comma-separated, max 50), beginDate (YYYY-MM-DD), endDate (YYYY-MM-DD)
      # Response: array of { advertId, days: [{ date (ISO8601), views, clicks, ... }] }
      def sync_ad_stats
        campaign_ids = RawWb::AdCampaign.where(account_id: @account.id).pluck(:wb_advert_id)
        return 0 if campaign_ids.empty?

        total = 0
        date_chunks(chunk_days: 31).each do |chunk_from, chunk_to|
          campaign_ids.each_slice(50) do |ids|
            data = @client.get(:advert, '/adv/v3/fullstats',
                               ids:       ids.join(','),
                               beginDate: chunk_from.iso8601,
                               endDate:   chunk_to.iso8601)
            daily_rows = []
            sku_rows   = []
            Array(data).each do |r|
              campaign = RawWb::AdCampaign.find_by(wb_advert_id: r['advertId'])
              next unless campaign
              build_ad_stat_rows(r, campaign).tap { |rows| daily_rows.concat(rows) }
              build_ad_sku_rows(r, campaign).tap  { |rows| sku_rows.concat(rows) }
            end

            if daily_rows.any?
              RawWb::AdDailyStat.upsert_all(daily_rows,
                unique_by: %i[campaign_id stat_date],
                update_only: %i[views clicks ctr cpc spend add_to_cart orders cr revenue])
            end
            if sku_rows.any?
              RawWb::AdSkuSpend.upsert_all(sku_rows,
                unique_by: :idx_raw_wb_ad_sku_spends_unique,
                update_only: %i[spend synced_at])
            end

            total += daily_rows.size
            sleep 2
          end
        end

        total
      end

      private

      def build_ad_stat_rows(r, campaign)
        Array(r['days']).filter_map do |d|
          stat_date = d['date'].to_s.first(10)
          next if stat_date.blank?
          {
            campaign_id: campaign.id,
            stat_date:   stat_date,
            views:       d['views'].to_i,
            clicks:      d['clicks'].to_i,
            ctr:         d['ctr'].to_f,
            cpc:         d['cpc'].to_f,
            spend:       d['sum'].to_f,
            add_to_cart: d['atbs'].to_i,
            orders:      d['orders'].to_i,
            cr:          d['cr'].to_f,
            revenue:     d['sum_price'].to_f,
          }
        end
      end

      # 解析 apps[].nms[] 层级，存每个 nm_id 每天的花费
      # 同一 (nm_id, stat_date) 可能跨多个 apps 重复出现，先聚合再输出
      def build_ad_sku_rows(r, campaign)
        aggregated = Hash.new(0.0)  # [nm_id, stat_date] => spend
        Array(r['days']).each do |d|
          stat_date = d['date'].to_s.first(10)
          next if stat_date.blank?
          Array(d['apps']).each do |app|
            Array(app['nms']).each do |nm|
              nm_id = nm['nmId'].to_i
              next unless nm_id.positive?
              aggregated[[nm_id, stat_date]] += nm['sum'].to_f
            end
          end
        end

        now = Time.current
        aggregated.map do |(nm_id, stat_date), spend|
          {
            campaign_id: campaign.id,
            nm_id:       nm_id,
            stat_date:   stat_date,
            spend:       spend,
            synced_at:   now,
          }
        end
      end
    end
  end
end
