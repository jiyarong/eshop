require "test_helper"

class SkuGradeInspectorScheduleTest < ActiveSupport::TestCase
  test "runs weekly after the operation action diagnosis" do
    recurring = YAML.safe_load_file(Rails.root.join("config/recurring.yml")).fetch("production")

    assert_equal "every tuesday at 04:10 in Asia/Shanghai",
      recurring.dig("sku_operation_action_effect_diagnosis", "schedule")
    assert_equal "AITasks::SkuGradeInspectorJob.perform_later",
      recurring.dig("sku_grade_inspector", "command")
    assert_equal "every tuesday at 05:10 in Asia/Shanghai",
      recurring.dig("sku_grade_inspector", "schedule")
  end
end
