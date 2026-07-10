require "test_helper"

class Reports::ToolSourceTemplateTest < ActiveSupport::TestCase
  test "can wrap inline tool script in an isolated scope with explicit exports" do
    template = Reports::ToolSourceTemplate.new(
      path: Rails.root.join("app/views/reports/tools/sources/roi_calculator_v1.html"),
      scope_class: "roi-tool-inline"
    )

    script = template.inline_script_content(
      initializer_name: "initializeEmbeddedRoiCalculator",
      wrap: true,
      export_statements: [
        "window.__roiCalculate = calculate;",
        "window.__roiInputMappings = inputMappings;"
      ]
    )

    assert_includes script, "(function() {"
    assert_includes script, "function initializeEmbeddedRoiCalculator() {"
    assert_includes script, "initializeEmbeddedRoiCalculator();"
    assert_includes script, "window.__roiCalculate = calculate;"
    assert_includes script, "window.__roiInputMappings = inputMappings;"
    assert_includes script, "})();"
  end
end
