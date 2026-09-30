require "test_helper"

class SkuDiagnosisScheduleTest < ActiveSupport::TestCase
  test "keeps one Tuesday SKU planning pipeline schedule" do
    recurring = YAML.safe_load_file(Rails.root.join("config/recurring.yml")).fetch("production")

    assert_equal "AITasks::SkuPlanningPipelineJob.perform_later",
      recurring.dig("sku_planning_pipeline", "command")
    assert_equal "every tuesday at 03:30 in Asia/Shanghai",
      recurring.dig("sku_planning_pipeline", "schedule")
    assert_nil recurring["sku_diagnosis"]

    %w[sku_inventory_health_check sku_operation_action_effect_diagnosis sku_grade_inspector sku_planner sku_operation_plan_evaluation].each do |task_name|
      assert_nil recurring[task_name], "#{task_name} should not be scheduled"
    end
  end
end
