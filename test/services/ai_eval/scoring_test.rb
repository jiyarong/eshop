# frozen_string_literal: true

require "test_helper"

class AiEvalScoringTest < ActiveSupport::TestCase
  def score(actual, assertions, **options)
    AiEval::Scoring.call(actual:, assertions:, dataset_version: "snapshot-1", oracle_version: "oracle-1", **options)
  end

  def oracle_assertions
    [
      { id: "severity", path: "$.severity", operator: "eq", expected: "critical", weight: 1, severity: "critical", category: "business" },
      { id: "tag", path: "$.tag", operator: "eq", expected: "stockout", weight: 9, category: "evidence" }
    ]
  end

  test "weighted score and critical gate are independent" do
    result = score({ "severity" => "warning", "tag" => "stockout" }, oracle_assertions, threshold: 80)
    assert_equal 90.0, result[:score]
    assert_equal "failed", result[:status]
    assert_equal ["severity"], result[:critical_failures]
    passed = score({ "severity" => "critical", "tag" => "stockout" }, oracle_assertions)
    assert_equal "passed", passed[:status]
  end

  test "category weights apply to score and missing weights block" do
    result = score({ "severity" => "warning", "tag" => "stockout" }, oracle_assertions,
      category_weights: { business: 40, evidence: 60 })
    assert_equal 60.0, result[:score]
    assert_equal "blocked", score({}, oracle_assertions, category_weights: { business: 100 })[:status]
    assert_equal "blocked", score({}, oracle_assertions, category_weights: { business: -1, evidence: 101 })[:status]
  end

  test "safety gates, unsupported assertions, empty oracle and duplicate IDs block" do
    assert_equal "blocked", score({}, [], gates: [{ name: "fixture_only", passed: false }])[:status]
    assert_equal "blocked", score({}, [])[:status]
    assert_equal "blocked", score({}, [{ operator: "semantic_fact" }])[:status]
    assert_equal "blocked", score({}, [{ operator: "eq", expected: {}, weight: -1 }])[:status]
    assert_equal "blocked", score({}, [{ operator: "eq", expected: {}, id: "same" }] * 2)[:status]
    assert_equal "blocked", score({}, [{ path: "$.missing", operator: "numeric_close", expected: "not a number" }])[:status]
    assert_equal "blocked", score({}, [{ path: "$.missing", operator: "range", expected: { min: 5, max: 1 } }])[:status]
  end

  test "baseline regression requires identical dataset and oracle versions" do
    baseline = score({ "severity" => "critical", "tag" => "stockout" }, oracle_assertions)
    current = score({ "severity" => "warning", "tag" => "stockout" }, oracle_assertions, baseline:)
    assert_equal(-10.0, current[:baseline_diff][:score_delta])
    assert_equal ["severity"], current[:baseline_diff][:newly_failed]
    assert current[:baseline_diff][:regression]
    mismatch = score({}, oracle_assertions, baseline: baseline.merge(oracle_version: "oracle-2"))
    assert_not mismatch[:baseline_diff][:comparable]
    assert_equal "version_mismatch", mismatch[:baseline_diff][:reason]
  end
end
