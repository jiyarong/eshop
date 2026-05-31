module RawOzon
  module Syncs
    module PerformanceAsyncReport
      private

      POLL_INTERVAL = 3   # seconds between status checks
      POLL_TIMEOUT  = 180 # give up after 3 minutes

      READY_STATES = %w[OK SUCCESS READY DONE].freeze

      # 提交异步报告后轮询至就绪，返回原始 body 字符串。
      # uuid   — POST 提交后返回的 UUID
      # client — 可选，传入独立 PerformanceClient 实例（并发场景每线程独立）；
      #          默认使用 @perf_client。
      def poll_and_download(uuid, client: nil)
        c        = client || @perf_client
        deadline = Time.current + POLL_TIMEOUT

        while Time.current < deadline
          status = c.get("/api/client/statistics/#{uuid}")
          state  = status['state'].to_s.upcase

          if READY_STATES.include?(state)
            return c.get_csv('/api/client/statistics/report', UUID: uuid)
          end

          raise PerformanceClient::ApiError, "Async report #{uuid} returned ERROR state" if state == 'ERROR'

          sleep POLL_INTERVAL
        end

        raise PerformanceClient::ApiError,
              "Async report #{uuid} timed out after #{POLL_TIMEOUT}s (last state: #{status&.dig('state')})"
      end
    end
  end
end
