require "test_helper"

class AITasks::SkuOperationActionEffectDiagnosisJobTest < ActiveJob::TestCase
  test "runs the operation action diagnosis for the requested date" do
    calls = []
    original_run = AITasks::SkuOperationActionEffectDiagnosis.method(:run)
    AITasks::SkuOperationActionEffectDiagnosis.define_singleton_method(:run) do |as_of_date:|
      calls << as_of_date
    end

    AITasks::SkuOperationActionEffectDiagnosisJob.perform_now(as_of_date: Date.new(2026, 8, 3))

    assert_equal [ Date.new(2026, 8, 3) ], calls
  ensure
    AITasks::SkuOperationActionEffectDiagnosis.define_singleton_method(:run, original_run) if original_run
  end
end
