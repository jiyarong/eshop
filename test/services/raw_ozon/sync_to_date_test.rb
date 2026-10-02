require "test_helper"

class RawOzonSyncToDateTest < ActiveSupport::TestCase
  def build_sync(**options)
    account = RawOzon::SellerAccount.new(client_id: "client", api_key: "key")
    RawOzon::DailySync.new(account, days: (Date.current - Date.new(2025, 1, 27)).to_i, **options)
  end

  test "each_day_in_range stops at the explicit to date" do
    days = []
    build_sync(to: "2025-02-02").send(:each_day_in_range) { |day| days << day }

    assert_equal "2025-01-27", days.first
    assert_equal "2025-02-02", days.last
    assert_equal 7, days.size
  end

  test "date_chunks and month_chunks stop at the explicit to date" do
    sync = build_sync(to: "2025-02-09")

    assert_equal Date.new(2025, 2, 9), sync.send(:date_chunks, chunk_days: 30).last.last
    assert_equal Date.new(2025, 2, 9), sync.send(:month_chunks).last.last
  end

  test "each_day_in_range defaults to today when to is omitted" do
    days = []
    build_sync.send(:each_day_in_range) { |day| days << day }

    assert_equal Date.current.to_s, days.last
  end
end
