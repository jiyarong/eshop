require "test_helper"
require "securerandom"

class RawOzonAdsCpcHistoryBackfillJobTest < ActiveJob::TestCase
  setup do
    token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(client_id: "ads-job-#{token}", api_key: token,
      company_type: "small", performance_client_id: "performance-#{token}", performance_client_secret: token)
    @unit = RawOzon::AdUnit.create!(account: @account, external_id: "101", unit_type: "cpc_campaign",
      state: "CAMPAIGN_STATE_RUNNING", raw_json: {}, synced_at: Time.current)
    @task = { "from_date" => "2026-07-01", "to_date" => "2026-07-22", "external_ids" => ["101"] }
  end

  teardown do
    clear_enqueued_jobs
    RawOzon::AdReportRun.where(account_id: @account.id).delete_all
    RawOzon::AdUnit.where(account_id: @account.id).delete_all
    @account.destroy!
  end

  test "skips a completed batch and enqueues the next task" do
    RawOzon::AdReportRun.create!(account: @account, report_type: "cpc_product_history",
      endpoint: "/api/client/statistics", period_from: "2026-07-01", period_to: "2026-07-22",
      state: "completed", request_body: { campaigns: ["101"], imported_at: Time.current.iso8601 })
    tasks = [@task, @task.merge("from_date" => "2026-07-23", "to_date" => "2026-07-24")]

    assert_enqueued_with(job: RawOzon::Ads::CpcHistoryBackfillJob, args: [@account.id, tasks, 1]) do
      RawOzon::Ads::CpcHistoryBackfillJob.perform_now(@account.id, tasks, 0)
    end
  end
end
