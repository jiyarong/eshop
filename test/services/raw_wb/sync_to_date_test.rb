require "test_helper"

class RawWbSyncToDateTest < ActiveSupport::TestCase
  def build_sync(**options)
    account = RawWb::SellerAccount.new(api_token: "test-token")
    RawWb::WeeklySync.new(account, days: (Date.current - Date.new(2025, 1, 27)).to_i, **options)
  end

  test "date_chunks stop at the explicit to date" do
    chunks = build_sync(to: "2025-02-09").send(:date_chunks, chunk_days: 1)

    assert_equal [Date.new(2025, 1, 27), Date.new(2025, 1, 27)], chunks.first
    assert_equal [Date.new(2025, 2, 9), Date.new(2025, 2, 9)], chunks.last
    assert_equal 14, chunks.size
  end

  test "natural_week_chunks stop at the explicit to date" do
    chunks = build_sync(to: "2025-02-09").send(:natural_week_chunks)

    assert_equal [[Date.new(2025, 1, 27), Date.new(2025, 2, 2)], [Date.new(2025, 2, 3), Date.new(2025, 2, 9)]], chunks
  end

  test "date_chunks default to today when to is omitted" do
    chunks = build_sync.send(:date_chunks, chunk_days: 31)

    assert_equal Date.current, chunks.last.last
  end
end
