require "digest"

module RawOzon
  module Ads
    class ReportRunner
      READY_STATES = %w[OK SUCCESS READY DONE].freeze
      POLL_INTERVAL = 3
      POLL_TIMEOUT = 600

      def initialize(account:, client:, poll_interval: POLL_INTERVAL, poll_timeout: POLL_TIMEOUT)
        @account = account
        @client = client
        @poll_interval = poll_interval
        @poll_timeout = poll_timeout
      end

      def run(report_type:, endpoint:, period_from:, period_to:, request_body:)
        report_run = RawOzon::AdReportRun.create!(
          account: @account,
          report_type: report_type,
          endpoint: endpoint,
          period_from: period_from,
          period_to: period_to,
          request_body: request_body,
          state: "submitting",
          attempts: 1,
          submitted_at: Time.current
        )

        response = yield
        uuid = response.fetch("UUID")
        report_run.update!(external_uuid: uuid, state: "processing")
        body = wait_for_report(uuid)
        report_run.update!(
          state: "completed",
          response_checksum: Digest::SHA256.hexdigest(body),
          completed_at: Time.current
        )
        body
      rescue => error
        report_run&.update_columns(state: "failed", error_message: error.message.to_s.truncate(1_000), completed_at: Time.current)
        raise
      end

      private

      def wait_for_report(uuid)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @poll_timeout

        loop do
          response = @client.get("/api/client/statistics/#{uuid}")
          state = response["state"].to_s.upcase
          return @client.get_csv("/api/client/statistics/report", UUID: uuid) if READY_STATES.include?(state)
          raise RawOzon::PerformanceClient::ApiError, "Report #{uuid} entered ERROR state" if state == "ERROR"
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            raise RawOzon::PerformanceClient::ApiError, "Report #{uuid} timed out after #{@poll_timeout}s"
          end

          sleep @poll_interval
        end
      end
    end
  end
end
