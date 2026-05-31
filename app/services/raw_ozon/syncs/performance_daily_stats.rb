module RawOzon
  module Syncs
    module PerformanceDailyStats
      # GET /api/client/statistics/daily — 同步广告每日统计
      # 分批请求（接口无活动数量上限限制，但保守起见每批 50 个）
      # API limit: max 62 days per request — chunk into 60-day windows
      def sync_performance_daily_stats
        campaigns = RawOzon::PerformanceCampaign.where(account_id: @account.id)
        return 0 if campaigns.none?

        chunks = date_chunks(chunk_days: 60)
        total  = 0

        chunks.each do |chunk_from, chunk_to|
          campaigns.each_slice(50) do |batch|
            ids      = batch.map(&:campaign_id).join(',')
            csv_body = @perf_client.get_csv(
              '/api/client/statistics/daily',
              campaigns: ids, dateFrom: chunk_from.to_s, dateTo: chunk_to.to_s
            )
            rows = parse_daily_stats_csv(csv_body, batch)
            next if rows.empty?

            RawOzon::PerformanceDailyStat.upsert_all(
              rows,
              unique_by: :idx_ozon_perf_daily_stats_unique,
              update_only: %i[impressions clicks spend orders_count orders_revenue synced_at]
            )
            total += rows.size
            sleep 0.5
          end
        end

        total
      end

      private

      # CSV 格式：ID;Название;Дата;Показы;Клики;Расход, ₽;Заказы, шт.;Заказы, ₽
      # 金额使用俄式逗号小数点，解析时需替换为 .
      def parse_daily_stats_csv(csv_body, campaigns)
        campaign_map = campaigns.index_by(&:campaign_id)
        synced_at    = Time.current
        rows         = []

        utf8_body = csv_body.dup.force_encoding('UTF-8')
        utf8_body = csv_body.dup.force_encoding('Windows-1251').encode('UTF-8', invalid: :replace, undef: :replace) unless utf8_body.valid_encoding?
        lines = utf8_body.split("\n")
        lines.drop(1).each do |line|           # 跳过表头
          cols = line.strip.split(';')
          next if cols.size < 8

          campaign_id_str = cols[0].strip
          campaign = campaign_map[campaign_id_str]
          next unless campaign

          rows << {
            account_id:     @account.id,
            campaign_id:    campaign.id,
            stat_date:      Date.parse(cols[2].strip),
            impressions:    cols[3].to_i,
            clicks:         cols[4].to_i,
            spend:          cols[5].strip.gsub(',', '.').to_d,
            orders_count:   cols[6].to_i,
            orders_revenue: cols[7].strip.gsub(',', '.').to_d,
            synced_at:      synced_at,
          }
        rescue ArgumentError
          next
        end

        rows
      end
    end
  end
end
