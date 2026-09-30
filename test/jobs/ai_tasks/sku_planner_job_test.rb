require "test_helper"

class AITasks::SkuPlannerJobTest < ActiveJob::TestCase
  test "manual planner retries when historical evaluation data is not ready" do
    with_planner(->(**) { raise Ec::SkuPlanningDataReadiness::NotReady, "source incomplete" }) do
      assert_enqueued_with(job: AITasks::SkuPlannerJob, args: [{ sku_code: "WAIT" }]) do
        AITasks::SkuPlannerJob.perform_now(sku_code: "WAIT")
      end
    end
  end

  test "manual planner retries when historical evaluation failed" do
    with_planner(->(**) { raise ErpAI::SkuPlannerRunner::EvaluationFailed, "AI unavailable" }) do
      assert_enqueued_with(job: AITasks::SkuPlannerJob, args: [{ sku_code: "FAILED" }]) do
        AITasks::SkuPlannerJob.perform_now(sku_code: "FAILED")
      end
    end
  end

  test "manual planner passes its SKU to the common runner" do
    arguments = nil
    with_planner(->(**args) { arguments = args }) do
      AITasks::SkuPlannerJob.perform_now(sku_code: "SKU-ONE")
    end
    assert_equal({ sku_code: "SKU-ONE" }, arguments)
  end

  test "enqueues one job per diagnosis sku for a batch" do
    date = Date.new(2026, 9, 29)
    requested_date = nil
    original_batch_sku_codes = ErpAI::SkuDiagnosisRunner.method(:batch_sku_codes)
    ErpAI::SkuDiagnosisRunner.define_singleton_method(:batch_sku_codes) do |as_of_date:|
      requested_date = as_of_date
      [ "SKU-ONE", "SKU-TWO" ]
    end

    assert_enqueued_jobs 2, only: AITasks::SkuPlannerJob do
      AITasks::SkuPlannerJob.perform_now(as_of_date: date)
    end
    assert_equal date, requested_date
  ensure
    ErpAI::SkuDiagnosisRunner.define_singleton_method(:batch_sku_codes, original_batch_sku_codes) if original_batch_sku_codes
  end

  test "limits concurrent planners to six" do
    assert_equal 6, AITasks::SkuPlannerJob.concurrency_limit
  end

  private

  def with_planner(replacement)
    original = ErpAI::SkuPlannerRunner.method(:run)
    ErpAI::SkuPlannerRunner.define_singleton_method(:run, replacement)
    yield
  ensure
    ErpAI::SkuPlannerRunner.define_singleton_method(:run, original)
  end
end
