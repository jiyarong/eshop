# frozen_string_literal: true

require "test_helper"

class AiEvalAssertionTest < ActiveSupport::TestCase
  def evaluate(actual, **assertion)
    AiEval::Assertion.call(actual:, assertion:)
  end

  test "scalar equality distinguishes missing and null" do
    assert evaluate({ "value" => nil }, path: "/value", operator: "eq", expected: nil)[:passed]
    assert_not evaluate({}, path: "/value", operator: "eq", expected: nil)[:passed]
    assert evaluate({}, path: "/value", operator: "exists", expected: false)[:passed]
    assert evaluate({ "value" => nil }, path: "/value", operator: "exists")[:passed]
  end

  test "membership and exclusion compare business facts" do
    actual = { "tags" => %w[stockout urgent], "severity" => "critical", "message" => "库存将在 7 天内耗尽" }
    assert evaluate(actual, path: "$.severity", operator: "one_of", expected: %w[warning critical])[:passed]
    assert evaluate(actual, path: "$.tags", operator: "include", expected: "stockout")[:passed]
    assert evaluate(actual, path: "$.tags", operator: "exclude", expected: %w[healthy overstock])[:passed]
    assert_not evaluate(actual, path: "$.tags", operator: "exclude", expected: %w[stockout healthy])[:passed]
    assert evaluate(actual, path: "$.message", operator: "include", expected: "7 天")[:passed]
  end

  test "numeric tolerance and range enforce numeric types" do
    assert evaluate({ "days" => 9.999 }, path: "$.days", operator: "numeric_close", expected: 10, tolerance: 0.01)[:passed]
    assert evaluate({ "days" => 9.999 }, path: "$.days", operator: "range", expected: { min: 9, max: 10 })[:passed]
    assert_not evaluate({ "days" => 10 }, path: "$.days", operator: "range", expected: { min: 10, inclusive_min: false })[:passed]
    assert_equal "error", evaluate({ "days" => "10" }, path: "$.days", operator: "numeric_close", expected: 10)[:status]
  end

  test "subset and safe wildcard JSONPath support listing collections" do
    actual = { "listings" => [{ "platform" => "ozon", "status" => "active" }, { "platform" => "wb", "status" => "paused" }] }
    assert evaluate(actual, path: "$.listings", operator: "subset", expected: [{ platform: "ozon" }])[:passed]
    assert evaluate(actual, path: "$.listings[*].platform", operator: "jsonpath", expected: %w[ozon wb])[:passed]
    assert evaluate(actual, path: "$['listings'][0].platform", operator: "eq", expected: "ozon")[:passed]
    assert_equal "error", evaluate(actual, path: "$.listings[?(@.x)]", operator: "exists")[:status]
  end

  test "semantic facts are explicitly unsupported and invalid weights are errors" do
    assert_equal "unsupported", evaluate({}, operator: "semantic_fact", expected: "stockout")[:status]
    assert_equal "error", evaluate({}, operator: "eq", expected: {}, weight: -1)[:status]
    assert_equal "error", evaluate({}, operator: "eq", expected: {}, weight: "nope")[:status]
  end
end
