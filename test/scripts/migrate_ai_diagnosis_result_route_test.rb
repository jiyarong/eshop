require "test_helper"
require Rails.root.join("script/migrate_ai_diagnosis_result_route")

class MigrateAIDiagnosisResultRouteTest < ActiveSupport::TestCase
  test "replaces absolute old route and adds diagnosis type" do
    input = <<~TEXT
      `POST /ai/skus/inventory_health_result`
      ```json
      {
        "sku": "SKU-CODE",
        "events": []
      }
      ```
    TEXT

    output = MigrateAIDiagnosisResultRoute.transform(input)

    assert_includes output, "POST /ai/diagnosis_results"
    assert_includes output, '"type": "RestockingDiagnosis"'
    assert_not_includes output, "inventory_health_result"
  end

  test "replaces relative old route and remains idempotent" do
    input = <<~TEXT
      `POST skus/inventory_health_result`
      {
      metrics: {},
      events: []
      }
    TEXT

    once = MigrateAIDiagnosisResultRoute.transform(input)

    assert_equal once, MigrateAIDiagnosisResultRoute.transform(once)
    assert_equal 1, once.scan('"type": "RestockingDiagnosis"').size
  end

  test "transforms nested recommended prompts without changing their structure" do
    input = ["Use POST /ai/skus/inventory_health_result\n{\n\"sku\": \"X\"\n}"]

    output = MigrateAIDiagnosisResultRoute.transform_value(input)

    assert_instance_of Array, output
    assert_includes output.first, "/ai/diagnosis_results"
    assert_includes output.first, '"type": "RestockingDiagnosis"'
  end
end
