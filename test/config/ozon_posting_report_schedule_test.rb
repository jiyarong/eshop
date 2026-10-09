require "test_helper"

class OzonPostingReportScheduleTest < ActiveSupport::TestCase
  test "syncs recent Ozon posting reports for buyer paid prices every day" do
    recurring = YAML.safe_load_file(Rails.root.join("config/recurring.yml")).fetch("production")

    assert_equal "every day at 9:40 in Asia/Shanghai", recurring.dig("ozon_posting_report_sync", "schedule")
    assert_equal "RawOzon::PostingReportSync.run_recent", recurring.dig("ozon_posting_report_sync", "command")
  end
end
