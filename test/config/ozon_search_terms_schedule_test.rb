require "test_helper"

class OzonSearchTermsScheduleTest < ActiveSupport::TestCase
  test "syncs completed search term weeks on monday and refreshes them on wednesday" do
    recurring = YAML.safe_load_file(Rails.root.join("config/recurring.yml")).fetch("production")

    assert_equal "every monday at 6:30 in Asia/Shanghai",
      recurring.dig("ozon_search_terms_weekly_sync", "schedule")
    assert_equal "every wednesday at 6:30 in Asia/Shanghai",
      recurring.dig("ozon_search_terms_midweek_refresh", "schedule")
    assert_includes recurring.dig("ozon_search_terms_weekly_sync", "command"),
      "sync_product_queries_through_friday"
    assert_includes recurring.dig("ozon_search_terms_midweek_refresh", "command"),
      "sync_product_queries"
    assert_not_includes recurring.dig("ozon_weekly_sync", "command"), "sync_product_queries"
  end
end
