require "test_helper"

class RawOzonPostingReportSyncTest < ActiveSupport::TestCase
  test "recent window looks back the requested number of days and stays inside the 93-day limit" do
    now = Time.utc(2026, 10, 9, 2, 0, 0)
    from, to = RawOzon::PostingReportSync.recent_window(days: 7, now: now)

    assert_equal now, to
    assert_equal now - 7.days, from
    assert_operator to - from, :<=, RawOzon::PostingReportSync::MAX_RANGE
    assert_raises(ArgumentError) { RawOzon::PostingReportSync.recent_window(days: 94, now: now) }
    assert_raises(ArgumentError) { RawOzon::PostingReportSync.recent_window(days: 0, now: now) }
  end

  test "run_recent creates no reports when there are no accounts" do
    assert_equal [], RawOzon::PostingReportSync.run_recent(days: 7, accounts: [])
  end

  test "splits exact 93-day ranges without gaps" do
    from = Time.utc(2026, 1, 1, 3, 4, 5)
    to = from + 200.days
    chunks = RawOzon::PostingReportSync.chunks(from, to)

    assert_equal [93.days, 93.days, 14.days], chunks.map { |left, right| right - left }
    assert_equal from, chunks.first.first
    assert_equal to, chunks.last.last
    assert_equal chunks[0].last, chunks[1].first
    assert_equal chunks[1].last, chunks[2].first
  end
end
