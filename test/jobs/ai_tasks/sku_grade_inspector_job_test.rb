require "test_helper"

class AITasks::SkuGradeInspectorJobTest < ActiveJob::TestCase
  test "runs the Grade inspector for the requested date and SKU" do
    calls = []
    original_run = AITasks::SkuGradeInspector.method(:run)
    AITasks::SkuGradeInspector.define_singleton_method(:run) do |as_of_date:, sku_code:|
      calls << [ as_of_date, sku_code ]
    end

    AITasks::SkuGradeInspectorJob.perform_now(
      as_of_date: Date.new(2026, 8, 4),
      sku_code: "GRADE-ONE"
    )

    assert_equal [ [ Date.new(2026, 8, 4), "GRADE-ONE" ] ], calls
  ensure
    AITasks::SkuGradeInspector.define_singleton_method(:run, original_run) if original_run
  end
end
