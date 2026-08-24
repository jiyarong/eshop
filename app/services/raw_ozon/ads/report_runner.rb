require "digest"

module RawOzon
  module Ads
    class ReportRunner
      READY_STATES = %w[OK SUCCESS READY DONE].freeze
      POLL_INTERVAL = 3
      POLL_TIMEOUT = 1_800

      class PollTimeout < RawOzon::PerformanceClient::ApiError; end

      def initialize(account:, client:, poll_interval: POLL_INTERVAL, poll_timeout: POLL_TIMEOUT)
        @account = account
        @client = client
        @poll_interval = poll_interval
        @poll_timeout = poll_timeout
      end

      def run(report_type:, endpoint:, period_from:, period_to:, request_body:)
        SyncRunLock.with_lock(lock_name, wait: true, logger: Rails.logger) do
          report_run = resumable_run(report_type, endpoint, period_from, period_to, request_body)
          report_run ||= create_run(report_type, endpoint, period_from, period_to, request_body)

          unless report_run.external_uuid.present?
            response = yield
            report_run.update!(external_uuid: response.fetch("UUID"), state: "processing")
          end

          body = wait_for_report(report_run.external_uuid)
          report_run.update!(state: "completed", response_checksum: Digest::SHA256.hexdigest(body),
            error_message: nil, completed_at: Time.current)
          body
        rescue PollTimeout => error
          # Keep the UUID resumable. A local timeout does not cancel the report in Ozon.
          report_run&.update_columns(state: "processing", error_message: error.message.to_s.truncate(1_000))
          raise
        rescue => error
          report_run&.update_columns(state: "failed", error_message: error.message.to_s.truncate(1_000),
            completed_at: Time.current)
          raise
        end
      end

      private

      def lock_name
        credential = @account.performance_client_id.presence || @account.id
        fingerprint = Digest::SHA256.hexdigest(credential.to_s).first(16)
        "raw_ozon:performance_async_report:#{fingerprint}"
      end

      def resumable_run(report_type, endpoint, period_from, period_to, request_body)
        RawOzon::AdReportRun.where(account: @account, report_type: report_type, endpoint: endpoint,
          period_from: period_from, period_to: period_to, state: "processing")
          .where.not(external_uuid: [nil, ""]).order(created_at: :desc)
          .detect { |run| run.request_body == request_body.deep_stringify_keys }
      end

      def create_run(report_type, endpoint, period_from, period_to, request_body)
        RawOzon::AdReportRun.create!(account: @account, report_type: report_type, endpoint: endpoint,
          period_from: period_from, period_to: period_to, request_body: request_body,
          state: "submitting", attempts: 1, submitted_at: Time.current)
      end

      def wait_for_report(uuid)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @poll_timeout

        loop do
          response = @client.get("/api/client/statistics/#{uuid}")
          state = response["state"].to_s.upcase
          return @client.get_csv("/api/client/statistics/report", UUID: uuid) if READY_STATES.include?(state)
          raise RawOzon::PerformanceClient::ApiError, "Report #{uuid} entered ERROR state" if state == "ERROR"
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            raise PollTimeout, "Report #{uuid} timed out after #{@poll_timeout}s"
          end

          sleep @poll_interval
        end
      end
    end
  end
end
