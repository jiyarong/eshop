require "test_helper"

class AITasks::SkuPlanningPipelineJobTest < ActiveJob::TestCase
  test "runs evaluation, diagnosis, then planner only after the diagnosis gate" do
    calls = []
    with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :run, ->(**args) { calls << [ :evaluation, args ] }) do
      with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :run, ->(**args) { calls << [ :diagnosis, args ] }) do
        with_stubbed_singleton_method(AITasks::SkuPlanningPipelineJob, :diagnosis_complete?, ->(**args) {
          calls << [ :gate, args ]
          true
        }) do
          with_stubbed_singleton_method(ErpAI::SkuPlannerRunner, :run, ->(**args) { calls << [ :planner, args ] }) do
            AITasks::SkuPlanningPipelineJob.perform_now(as_of_date: Date.new(2026, 9, 28), sku_code: "SKU-ONE")
          end
        end
      end
    end

    assert_equal [ :evaluation, :diagnosis, :gate, :planner ], calls.map(&:first)
    assert_equal({ as_of_date: Date.new(2026, 9, 28), sku_code: "SKU-ONE" }, calls[0].last)
    assert_equal({ as_of_date: Date.new(2026, 9, 28), sku_code: "SKU-ONE" }, calls[1].last)
    assert_equal({ sku_code: "SKU-ONE", as_of_date: Date.new(2026, 9, 28), rerun: false }, calls[3].last)
  end

  test "can resume at planner without rerunning earlier stages" do
    calls = []
    with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :run, ->(**) { calls << :evaluation }) do
      with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :run, ->(**) { calls << :diagnosis }) do
        with_stubbed_singleton_method(AITasks::SkuPlanningPipelineJob, :diagnosis_complete?, ->(**args) {
          calls << [ :gate, args ]
          true
        }) do
          with_stubbed_singleton_method(ErpAI::SkuPlannerRunner, :run, ->(**) { calls << :planner }) do
            AITasks::SkuPlanningPipelineJob.perform_now(stage: "planner", sku_code: "SKU-ONE")
          end
        end
      end
    end

    assert_equal [ :gate, :planner ], calls.map { |entry| entry.is_a?(Array) ? entry.first : entry }
    assert_nil calls.first.last[:started_at]
  end

  test "does not call planner when diagnosis is incomplete" do
    planner_called = false
    with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :run, ->(**) {}) do
      with_stubbed_singleton_method(ErpAI::SkuDiagnosisRunner, :run, ->(**) {}) do
        with_stubbed_singleton_method(AITasks::SkuPlanningPipelineJob, :diagnosis_complete?, ->(**) { false }) do
          with_stubbed_singleton_method(ErpAI::SkuPlannerRunner, :run, ->(**) { planner_called = true }) do
            assert_enqueued_with(
              job: AITasks::SkuPlanningPipelineJob,
              args: [ { sku_code: "SKU-ONE" } ]
            ) do
              AITasks::SkuPlanningPipelineJob.perform_now(sku_code: "SKU-ONE")
            end
          end
        end
      end
    end

    assert_not planner_called
  end

  private

  def with_stubbed_singleton_method(object, method_name, replacement)
    original_method = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original_method)
  end
end
