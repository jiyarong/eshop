require "test_helper"

class RawOzonPostingReportSyncTest < ActiveSupport::TestCase
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
