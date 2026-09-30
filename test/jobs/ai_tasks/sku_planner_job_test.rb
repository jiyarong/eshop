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

  private

  def with_planner(replacement)
    original = ErpAI::SkuPlannerRunner.method(:run)
    ErpAI::SkuPlannerRunner.define_singleton_method(:run, replacement)
    yield
  ensure
    ErpAI::SkuPlannerRunner.define_singleton_method(:run, original)
  end
end
