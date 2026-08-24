module RawOzon
  module Syncs
    module PerformancePpcSkuSpends
      ARCHIVED_STATE = "CAMPAIGN_STATE_ARCHIVED"
      ARCHIVED_CAMPAIGN_LOOKBACK_MONTHS = 4

      # POST /api/client/statistics/json（异步，每批 ≤10 campaigns）
      # 用 totals.moneySpent 对 per-SKU rows 归一化，消除日舍入误差。
      # 限制：同时只允许 1 个异步报告在处理，必须完全串行（提交→等完成→再提交下一批）。

      def sync_performance_ppc_sku_spends
        campaign_ids = ppc_campaign_ids
        return 0 if campaign_ids.empty?

        period_from = @from.to_date
        period_to   = @to
        batches     = campaign_ids.each_slice(10).to_a

        # 完全串行：提交 → poll 完成下载 → 再提交下一批
        sku_spends = Hash.new(0.0)
        batches.each_with_index do |batch, idx|
          log "  PPC batch #{idx + 1}/#{batches.size} 提交..."
          begin
            request = {
              campaigns: batch,
              dateFrom:  period_from.to_s,
              dateTo:    period_to.to_s,
              groupBy:   'DATE',
            }
            raw = @report_runner.run(report_type: "performance_ppc_sku_spends",
              endpoint: "/api/client/statistics/json", period_from: period_from, period_to: period_to,
              request_body: request) do
              @perf_client.post('/api/client/statistics/json', request)
            end
            accumulate_ppc_spends(JSON.parse(raw), sku_spends) if raw
          rescue RawOzon::Ads::ReportRunner::PollTimeout, PerformanceClient::RetryableError => e
            log "  PPC batch #{idx + 1}/#{batches.size} 暂停: #{e.message}", level: :warn
            raise
          rescue PerformanceClient::ApiError => e
            log "  PPC batch #{idx + 1}/#{batches.size} 失败: #{e.message}", level: :warn
          ensure
            sleep 15 if idx < batches.size - 1  # 批次间冷却，等 API slot 释放
          end
        end

        return 0 if sku_spends.empty?

        synced_at = Time.current
        RawOzon::PerformanceSkuSpend
          .where(account_id: @account.id, period_from: period_from, period_to: period_to, ad_type: 'ppc')
          .delete_all

        rows = sku_spends.map do |sku_str, spend|
          {
            account_id:  @account.id,
            period_from: period_from,
            period_to:   period_to,
            ad_type:     'ppc',
            ozon_sku_id: sku_str.to_i,
            spend:       spend.round(2),
            synced_at:   synced_at,
          }
        end

        RawOzon::PerformanceSkuSpend.insert_all(rows)
        rows.size
      end

      private

      def ppc_campaign_ids
        scope = RawOzon::AdUnit.where(account_id: @account.id, unit_type: "cpc_campaign")
        cutoff = @to.advance(months: -ARCHIVED_CAMPAIGN_LOOKBACK_MONTHS)

        scope
          .where.not(state: ARCHIVED_STATE)
          .or(scope.where(state: nil))
          .or(scope.where(state: ARCHIVED_STATE, from_date: nil))
          .or(scope.where(state: ARCHIVED_STATE, from_date: cutoff..))
          .pluck(:external_id)
      end

      def fetch_ppc_json(campaign_ids, period_from, period_to)
        request = {
          campaigns: campaign_ids,
          dateFrom:  period_from.to_s,
          dateTo:    period_to.to_s,
          groupBy:   'DATE',
        }
        raw = @report_runner.run(report_type: "performance_ppc_sku_spends",
          endpoint: "/api/client/statistics/json", period_from: period_from, period_to: period_to,
          request_body: request) do
          @perf_client.post('/api/client/statistics/json', request)
        end
        raw ? JSON.parse(raw) : nil
      rescue PerformanceClient::ApiError => e
        log "  PPC batch #{campaign_ids.first}…#{campaign_ids.last}: #{e.message}", level: :warn
        nil
      end

      # report_json: {campaign_id => {title:, report: {rows:[], totals:{}}}}
      def accumulate_ppc_spends(report_json, sku_spends)
        report_json.each_value do |campaign_data|
          report      = campaign_data['report'] || {}
          rows        = Array(report['rows'])
          total_spent = report.dig('totals', 'moneySpent').to_f
          next if total_spent.zero?

          raw_by_sku = Hash.new(0.0)
          rows.each do |row|
            sku = row['sku'].to_s
            next if sku.empty?
            raw_by_sku[sku] += row['moneySpent'].to_f
          end

          raw_sum = raw_by_sku.values.sum
          next if raw_sum.zero?

          scale = total_spent / raw_sum
          raw_by_sku.each { |sku, v| sku_spends[sku] += v * scale }
        end
      end
    end
  end
end
