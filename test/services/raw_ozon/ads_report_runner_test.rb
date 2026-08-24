require "test_helper"
require "securerandom"

class RawOzonAdsReportRunnerTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :status_requests

    def initialize(state: "OK")
      @state = state
      @status_requests = 0
    end

    def get(path, params = {})
      if path == "/api/client/statistics/report-1"
        @status_requests += 1
        return { "state" => @state }
      end
      raise "unexpected GET #{path} #{params.inspect}"
    end

    def get_csv(path, params = {})
      raise "unexpected CSV #{path}" unless path == "/api/client/statistics/report" && params[:UUID] == "report-1"
      "SKU;Расход, ₽\n3001;10,00\n"
    end
  end

  setup do
    token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(client_id: "ads-report-#{token}", api_key: token, company_type: "small")
  end

  teardown do
    RawOzon::AdReportRun.where(account_id: @account.id).delete_all
    RawOzon::SellerAccount.where(id: @account.id).delete_all
  end

  test "records completed asynchronous report without storing report contents" do
    runner = RawOzon::Ads::ReportRunner.new(account: @account, client: FakeClient.new, poll_interval: 0, poll_timeout: 1)
    body = runner.run(
      report_type: "cpo_selected_products",
      endpoint: "/api/client/statistic/products/generate",
      period_from: Date.new(2026, 7, 22),
      period_to: Date.new(2026, 7, 22),
      request_body: { from: "2026-07-22T00:00:00+03:00" }
    ) { { "UUID" => "report-1" } }

    assert_match "SKU", body
    report = RawOzon::AdReportRun.find_by!(account_id: @account.id)
    assert_equal "completed", report.state
    assert_equal "report-1", report.external_uuid
    assert_predicate report.response_checksum, :present?
    assert_nil report.error_message
  end

  test "resumes a processing report without submitting a duplicate" do
    request = { campaigns: ["101"], dateFrom: "2026-07-22" }
    RawOzon::AdReportRun.create!(account: @account, report_type: "cpc_product_history",
      endpoint: "/api/client/statistics", period_from: Date.new(2026, 7, 22),
      period_to: Date.new(2026, 7, 22), request_body: request, state: "processing",
      external_uuid: "report-1", submitted_at: Time.current)
    runner = RawOzon::Ads::ReportRunner.new(account: @account, client: FakeClient.new,
      poll_interval: 0, poll_timeout: 1)

    body = runner.run(report_type: "cpc_product_history", endpoint: "/api/client/statistics",
      period_from: Date.new(2026, 7, 22), period_to: Date.new(2026, 7, 22), request_body: request) do
      flunk "must not submit a second report"
    end

    assert_match "SKU", body
    assert_equal "completed", RawOzon::AdReportRun.last.state
  end

  test "keeps report processing after local polling timeout" do
    client = FakeClient.new(state: "NOT_STARTED")
    runner = RawOzon::Ads::ReportRunner.new(account: @account, client: client,
      poll_interval: 0, poll_timeout: 0)

    assert_raises(RawOzon::Ads::ReportRunner::PollTimeout) do
      runner.run(report_type: "cpc_product_history", endpoint: "/api/client/statistics",
        period_from: Date.new(2026, 7, 22), period_to: Date.new(2026, 7, 22),
        request_body: { campaigns: ["101"] }) { { "UUID" => "report-1" } }
    end

    report = RawOzon::AdReportRun.last
    assert_equal "processing", report.state
    assert_equal "report-1", report.external_uuid
    assert_nil report.completed_at
  end
end
