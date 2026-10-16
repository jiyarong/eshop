require "test_helper"

# The workbench page rebuilds every calculation step in JavaScript
# (app/javascript/controllers/profit_prediction_formula.js) and its spec checks those formulas
# against the figures stored in this fixture. This test keeps the fixture equal to what the
# Ruby calculators produce now, so a calculator change cannot leave the page formulas behind.
class Ec::ProfitPredictionFormulaCasesTest < ActiveSupport::TestCase
  CASES = JSON.parse(File.read(Rails.root.join("test/fixtures/files/profit_prediction_formula_cases.json")))

  CASES.each do |kase|
    test "the calculator still produces the figures recorded for #{kase['name']}" do
      result = Ec::ProfitCalculator.call(platform: kase["platform"], parameter_context: kase["context"], inputs: kase["inputs"])
      expected = kase["expected"]

      assert_empty result[:errors].to_a
      %w[revenue_cny total_cost_cny profit_cny margin].each do |key|
        assert_in_delta expected[key], result[key.to_sym].to_f, 1e-9, key
      end
      expected["cost_breakdown"].each do |key, value|
        assert_in_delta value, result[:cost_breakdown].fetch(key.to_sym).to_f, 1e-9, "cost_breakdown.#{key}"
      end
      expected["intermediate"].each do |key, value|
        actual = result[:intermediate][key.to_sym]
        if value.is_a?(Numeric)
          assert_in_delta value, actual.to_f, 1e-9, "intermediate.#{key}"
        else
          assert_equal value, actual, "intermediate.#{key}"
        end
      end
    end
  end
end
