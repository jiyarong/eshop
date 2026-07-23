require "test_helper"

class RawOzonAdsCpcHistoryBackfillTest < ActiveSupport::TestCase
  test "splits history into 62 day periods and batches of 10 campaigns" do
    tasks = RawOzon::Ads::CpcHistoryBackfill.build_tasks(
      from_date: Date.new(2026, 1, 1), to_date: Date.new(2026, 3, 10),
      external_ids: (1..11).map(&:to_s)
    )

    assert_equal 4, tasks.size
    assert_equal "2026-01-01", tasks.first.fetch("from_date")
    assert_equal "2026-03-04", tasks.third.fetch("from_date")
    assert_equal 10, tasks.first.fetch("external_ids").size
    assert_equal ["11"], tasks.second.fetch("external_ids")
  end

  test "rejects an inverted date range" do
    assert_raises(ArgumentError) do
      RawOzon::Ads::CpcHistoryBackfill.build_tasks(
        from_date: Date.new(2026, 2, 1), to_date: Date.new(2026, 1, 1), external_ids: ["1"]
      )
    end
  end
end
