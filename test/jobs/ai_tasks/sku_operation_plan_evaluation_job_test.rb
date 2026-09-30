require "test_helper"

class AITasks::SkuOperationPlanEvaluationJobTest < ActiveJob::TestCase
  test "passes a requested period and plan to the evaluation runner with the default agent client" do
    calls = []
    original_run = Ec::SkuOperationPlanEvaluationRunner.method(:run)
    Ec::SkuOperationPlanEvaluationRunner.define_singleton_method(:run) do |**arguments|
      calls << arguments
    end

    AITasks::SkuOperationPlanEvaluationJob.perform_now(
      as_of_date: Date.new(2026, 9, 29),
      period_start: Date.new(2026, 9, 21),
      plan_id: 42,
      sku_code: "SKU-42"
    )

    assert_equal Date.new(2026, 9, 29), calls.sole[:as_of_date]
    assert_equal Date.new(2026, 9, 21), calls.sole[:period_start]
    assert_equal 42, calls.sole[:plan_id]
    assert_equal "SKU-42", calls.sole[:sku_code]
    assert_instance_of ErpAI::DefaultClient, calls.sole[:client]
    assert_equal "sku_plan_evaluation", calls.sole.fetch(:agent).code
    assert calls.sole.fetch(:force)
  ensure
    Ec::SkuOperationPlanEvaluationRunner.define_singleton_method(:run, original_run) if original_run
  end
end
