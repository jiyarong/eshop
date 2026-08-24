require "test_helper"
require "securerandom"

class RawOzonAdsReportRunnerTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :status_requests

    def initialize(state: "OK", external_reports: [])
      @state = state
      @external_reports = external_reports
      @status_requests = 0
    end

    def get(path, params = {})
      return { "items" => @external_reports } if path == "/api/client/statistics/externallist"

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

  test "adopts a matching active ppc report from Ozon" do
    request = { campaigns: %w[101 102], dateFrom: "2026-07-22", dateTo: "2026-07-23" }
    external = [{ "meta" => { "UUID" => "report-1", "state" => "IN_PROGRESS", "request" => {
      "campaigns" => %w[102 101], "from" => "2026-07-21T21:00:00Z", "to" => "2026-07-23T20:59:59Z"
    } } }]
    runner = RawOzon::Ads::ReportRunner.new(account: @account,
      client: FakeClient.new(external_reports: external), poll_interval: 0, poll_timeout: 1)

    body = runner.run(report_type: "performance_ppc_sku_spends", endpoint: "/api/client/statistics/json",
      period_from: Date.new(2026, 7, 22), period_to: Date.new(2026, 7, 23), request_body: request) do
      flunk "must adopt the active Ozon report"
    end

    assert_match "SKU", body
    report = RawOzon::AdReportRun.last
    assert_equal "report-1", report.external_uuid
    assert_equal "completed", report.state
  end

  test "reuses a recently completed matching report" do
    request = { campaigns: ["101"], dateFrom: "2026-07-22" }
    RawOzon::AdReportRun.create!(account: @account, report_type: "performance_ppc_sku_spends",
      endpoint: "/api/client/statistics/json", period_from: Date.new(2026, 7, 22),
      period_to: Date.new(2026, 7, 22), request_body: request, state: "completed",
      external_uuid: "report-1", submitted_at: 1.hour.ago, completed_at: Time.current)
    runner = RawOzon::Ads::ReportRunner.new(account: @account, client: FakeClient.new,
      poll_interval: 0, poll_timeout: 1)

    runner.run(report_type: "performance_ppc_sku_spends", endpoint: "/api/client/statistics/json",
      period_from: Date.new(2026, 7, 22), period_to: Date.new(2026, 7, 22), request_body: request) do
      flunk "must reuse the completed report"
    end

    assert_equal 1, RawOzon::AdReportRun.where(account: @account).count
  end

  test "does not submit while an unrelated Ozon report occupies the slot" do
    external = [{ "meta" => { "UUID" => "other-report", "state" => "NOT_STARTED", "request" => {
      "campaigns" => ["999"], "from" => "2026-07-21T21:00:00Z", "to" => "2026-07-22T20:59:59Z"
    } } }]
    runner = RawOzon::Ads::ReportRunner.new(account: @account,
      client: FakeClient.new(external_reports: external), poll_interval: 0, poll_timeout: 0)

    assert_raises(RawOzon::Ads::ReportRunner::SlotTimeout) do
      runner.run(report_type: "performance_ppc_sku_spends", endpoint: "/api/client/statistics/json",
        period_from: Date.new(2026, 7, 22), period_to: Date.new(2026, 7, 22),
        request_body: { campaigns: ["101"], dateFrom: "2026-07-22", dateTo: "2026-07-22" }) do
        flunk "must not submit while the slot is occupied"
      end
    end

    assert_not RawOzon::AdReportRun.where(account: @account).exists?
  end

  test "ignores import metadata when reusing a completed report" do
    request = { campaigns: ["101"], dateFrom: "2026-07-22" }
    RawOzon::AdReportRun.create!(account: @account, report_type: "cpc_product_history",
      endpoint: "/api/client/statistics", period_from: Date.new(2026, 7, 22),
      period_to: Date.new(2026, 7, 22), request_body: request.merge(imported_at: Time.current.iso8601,
        imported_rows: 3), state: "completed", external_uuid: "report-1",
      submitted_at: 1.hour.ago, completed_at: Time.current)
    runner = RawOzon::Ads::ReportRunner.new(account: @account, client: FakeClient.new,
      poll_interval: 0, poll_timeout: 1)

    runner.run(report_type: "cpc_product_history", endpoint: "/api/client/statistics",
      period_from: Date.new(2026, 7, 22), period_to: Date.new(2026, 7, 22), request_body: request) do
      flunk "must reuse the imported report"
    end

    assert_equal 1, RawOzon::AdReportRun.where(account: @account).count
  end
end
