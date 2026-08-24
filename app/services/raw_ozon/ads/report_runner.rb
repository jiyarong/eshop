require "digest"

module RawOzon
  module Ads
    class ReportRunner
      READY_STATES = %w[OK SUCCESS READY DONE].freeze
      POLL_INTERVAL = 3
      POLL_TIMEOUT = 1_800
      COMPLETED_REUSE_WINDOW = 24.hours

      class PollTimeout < RawOzon::PerformanceClient::ApiError; end
      class SlotTimeout < RawOzon::PerformanceClient::ApiError; end

      def initialize(account:, client:, poll_interval: POLL_INTERVAL, poll_timeout: POLL_TIMEOUT)
        @account = account
        @client = client
        @poll_interval = poll_interval
        @poll_timeout = poll_timeout
      end

      def run(report_type:, endpoint:, period_from:, period_to:, request_body:)
        SyncRunLock.with_lock(lock_name, wait: true, logger: Rails.logger) do
          report_run = resumable_run(report_type, endpoint, period_from, period_to, request_body)
          unless report_run
            external_report = wait_for_available_slot(request_body)
            report_run = external_report ? adopt_run(report_type, endpoint, period_from, period_to,
              request_body, external_report) : create_run(report_type, endpoint, period_from, period_to, request_body)
          end

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
          period_from: period_from, period_to: period_to, state: %w[processing completed])
          .where("submitted_at >= ?", COMPLETED_REUSE_WINDOW.ago)
          .where.not(external_uuid: [nil, ""]).order(created_at: :desc)
          .detect { |run| request_payload(run.request_body) == request_payload(request_body) }
      end

      def request_payload(request)
        request.deep_stringify_keys.except("imported_at", "imported_rows")
      end

      def wait_for_available_slot(request_body)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @poll_timeout

        loop do
          active_reports = external_reports.select { |report| %w[NOT_STARTED IN_PROGRESS].include?(report[:state]) }
          return nil if active_reports.empty?

          matching = active_reports.find { |report| same_ppc_request?(report[:request], request_body) }
          return matching if matching

          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            uuids = active_reports.map { |report| report[:uuid] }.compact.join(",")
            raise SlotTimeout, "Performance report slot remained occupied after #{@poll_timeout}s (UUIDs: #{uuids})"
          end

          Rails.logger.info("[OzonReportRunner] waiting for active report slot account=#{@account.id} " \
            "uuid=#{active_reports.first[:uuid]} state=#{active_reports.first[:state]}")
          sleep @poll_interval
        end
      end

      def external_reports
        response = @client.get("/api/client/statistics/externallist", page: 1, pageSize: 100)
        Array(response["items"]).map do |item|
          meta = item["meta"] || {}
          { uuid: meta["UUID"], state: meta["state"].to_s.upcase, request: meta["request"] || {} }
        end
      end

      def same_ppc_request?(external_request, request_body)
        expected_campaigns = Array(request_body[:campaigns] || request_body["campaigns"]).map(&:to_s).sort
        actual_campaigns = Array(external_request["campaigns"]).map(&:to_s).sort
        return false if expected_campaigns.empty? || expected_campaigns != actual_campaigns

        expected_from = request_date(request_body, "dateFrom", "from")
        expected_to = request_date(request_body, "dateTo", "to")
        actual_from = request_date(external_request, "dateFrom", "from")
        actual_to = request_date(external_request, "dateTo", "to")
        expected_from == actual_from && expected_to == actual_to
      end

      def request_date(request, date_key, time_key)
        value = request[date_key] || request[date_key.to_sym]
        value = request[time_key] || request[time_key.to_sym] if value.blank?
        return if value.blank?

        Time.iso8601(value.to_s).in_time_zone("Europe/Moscow").to_date
      rescue ArgumentError
        Date.parse(value.to_s)
      end

      def adopt_run(report_type, endpoint, period_from, period_to, request_body, external_report)
        RawOzon::AdReportRun.create!(account: @account, report_type: report_type, endpoint: endpoint,
          period_from: period_from, period_to: period_to, request_body: request_body,
          state: "processing", attempts: 1, submitted_at: Time.current, external_uuid: external_report[:uuid])
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
