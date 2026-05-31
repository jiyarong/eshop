module RawWb
  module Syncs
    module PaidStorage
      POLL_ATTEMPTS = 60
      POLL_INTERVAL = 5  # seconds

      # GET /api/v1/paid_storage          — 创建异步任务（API 限制：dateFrom~dateTo ≤ 8 天）
      # GET /api/v1/paid_storage/tasks/:id/status   — 轮询状态
      # GET /api/v1/paid_storage/tasks/:id/download — 下载结果
      #
      # API 返回的是按 chrtId×仓库×日期 的明细行，存入 DB 前按 (nm_id, calc_date) 预聚合。
      def sync_paid_storage
        total = 0
        date_chunks(chunk_days: 7).each do |from_dt, to_dt|
          task_id = create_paid_storage_task(from_dt, to_dt)
          wait_for_paid_storage_task(task_id)
          total += download_and_store_paid_storage(task_id)
          sleep 30
        end
        total
      end

      private

      def create_paid_storage_task(from_dt, to_dt)
        resp    = @client.get(:seller_analytics, '/api/v1/paid_storage',
                    dateFrom: from_dt.iso8601, dateTo: to_dt.iso8601)
        task_id = resp.dig('data', 'taskId') || resp['taskId']
        raise RawWb::WbClient::ApiError, 'paid_storage: no taskId in response' if task_id.blank?
        task_id
      end

      def wait_for_paid_storage_task(task_id)
        POLL_ATTEMPTS.times do
          resp   = @client.get(:seller_analytics, "/api/v1/paid_storage/tasks/#{task_id}/status")
          status = resp.dig('data', 'status') || resp['status']
          return if status == 'done'
          raise RawWb::WbClient::ApiError, "paid_storage task failed: #{status}" if status == 'error'
          sleep POLL_INTERVAL
        end
        raise RawWb::WbClient::ApiError,
              "paid_storage task timed out after #{POLL_ATTEMPTS * POLL_INTERVAL}s"
      end

      def download_and_store_paid_storage(task_id)
        resp = nil
        10.times do |i|
          begin
            resp = @client.get(:seller_analytics, "/api/v1/paid_storage/tasks/#{task_id}/download")
            break
          rescue RawWb::WbClient::RetryableError
            wait = 60 * (i + 1)  # 60s, 120s, 180s ...
            log "  ⏳ paid_storage download rate-limited, waiting #{wait}s...", level: :warn
            sleep wait
          end
        end
        items = resp.is_a?(Array) ? resp : Array(resp&.dig('data') || resp || [])
        return 0 if items.empty?

        # 按 (nm_id, calc_date) 预聚合 — 汇总同一 nmId 当天各仓库的费用
        aggregated = Hash.new { |h, k| h[k] = { price: 0.0, vendor_code: nil } }
        items.each do |r|
          nm_id   = r['nmId']
          calc_dt = r['date'].presence&.to_date
          next if nm_id.blank? || calc_dt.nil?

          key = [nm_id, calc_dt]
          aggregated[key][:price]       += r['warehousePrice'].to_f
          aggregated[key][:vendor_code] ||= r['vendorCode']
        end

        rows = aggregated.map do |(nm_id, calc_dt), v|
          {
            account_id:         @account.id,
            nm_id:              nm_id,
            vendor_code:        v[:vendor_code],
            warehouse_price_rub: v[:price],
            calc_date:          calc_dt,
            synced_at:          Time.current,
          }
        end

        RawWb::PaidStorage.upsert_all(
          rows,
          unique_by: :idx_raw_wb_paid_storages_unique,
          update_only: %i[warehouse_price_rub synced_at]
        ) if rows.any?

        rows.size
      end
    end
  end
end
