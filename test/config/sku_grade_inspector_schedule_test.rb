require "test_helper"

class SkuDiagnosisScheduleTest < ActiveSupport::TestCase
  test "keeps only the general SKU AI diagnosis schedule" do
    recurring = YAML.safe_load_file(Rails.root.join("config/recurring.yml")).fetch("production")

    assert_equal "AITasks::SkuDiagnosisJob.perform_later",
      recurring.dig("sku_diagnosis", "command")
    assert_equal "every tuesday at 03:30 in Asia/Shanghai",
      recurring.dig("sku_diagnosis", "schedule")

    %w[sku_inventory_health_check sku_operation_action_effect_diagnosis sku_grade_inspector].each do |task_name|
      assert_nil recurring[task_name], "#{task_name} should not be scheduled"
    end
  end
end
