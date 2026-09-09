module RawOzon
  class PostingReportPollJob < ApplicationJob
    queue_as :default

    WAITING_STATUSES = %w[waiting processing creating].freeze
    SUCCESS_STATUSES = %w[success completed done].freeze
    MAX_ATTEMPTS = 60

    def perform(report_id, attempt: 1)
      report = RawOzon::Report.find(report_id)
      client = RawOzon::OzonClient.new(report.account.client_id, report.account.api_key)
      response = client.post("/v1/report/info", "code" => report.report_code)
      status = (response.dig("result", "status") || response["status"]).to_s.downcase
      file_url = response.dig("result", "file") || response.dig("result", "file_url") || response["file_url"]
      report.update!(status:, file_url:, raw_json: response)

      if WAITING_STATUSES.include?(status)
        return fail_report(report, "Ozon report polling timed out") if attempt >= MAX_ATTEMPTS
        self.class.set(wait: 1.minute).perform_later(report.id, attempt: attempt + 1)
      elsif SUCCESS_STATUSES.include?(status)
        import(report, client, file_url)
      else
        fail_report(report, response.dig("result", "error") || response["error"] || "Ozon report failed with status #{status.inspect}")
      end
    rescue => e
      report&.update!(status: "failed", error: "#{e.class}: #{e.message}")
      raise
    end

    private

    def import(report, client, file_url)
      raise RawOzon::PostingReportCsvParser::InvalidReport, "Ozon report response has no file URL" if file_url.blank?

      download = client.download(file_url)
      stats = RawOzon::PostingReportImport.new(
        report:,
        body: download.fetch(:body),
        buyer_paid_value_kind: report.params.fetch("buyer_paid_value_kind")
      ).call
      report.update!(status: "imported", synced_at: Time.current, error: nil, raw_json: report.raw_json.merge("import_stats" => stats.stringify_keys))
    end

    def fail_report(report, error)
      report.update!(status: "failed", error: error)
    end
  end
end
