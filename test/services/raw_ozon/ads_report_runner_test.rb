require "test_helper"
require "securerandom"

class RawOzonAdsReportRunnerTest < ActiveSupport::TestCase
  class FakeClient
    def get(path, params = {})
      return { "state" => "OK" } if path == "/api/client/statistics/report-1"
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
end
