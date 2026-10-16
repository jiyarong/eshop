# frozen_string_literal: true

module AiEval
  class Scoring
    DEFAULT_THRESHOLD = 90.0
    CATEGORY_WEIGHTS = {
      "diagnosis" => { "structure" => 15, "business" => 40, "evidence" => 20, "missing_data" => 15, "tools" => 10 },
      "planner" => { "structure" => 15, "business" => 35, "evidence" => 20, "missing_data" => 10, "tools" => 20 },
      "activepieces" => { "structure" => 15, "business" => 35, "evidence" => 25, "missing_data" => 15, "tools" => 10 },
      "evaluation" => { "structure" => 15, "business" => 35, "evidence" => 25, "missing_data" => 15, "tools" => 10 }
    }.freeze

    def self.call(actual:, assertions:, **options)
      new(actual:, assertions:, **options).call
    end

    def initialize(actual:, assertions:, threshold: DEFAULT_THRESHOLD, category_weights: {}, gates: [], baseline: nil,
      dataset_version: nil, oracle_version: nil)
      @actual, @assertions = actual, Array(assertions)
      @threshold = Float(threshold)
      @category_weights = category_weights.to_h.stringify_keys
      @gates = Array(gates).map { |gate| gate.to_h.symbolize_keys }
      @baseline, @dataset_version, @oracle_version = baseline, dataset_version, oracle_version
    end

    def call
      assertions = @assertions.map { |assertion| Assertion.call(actual: @actual, assertion:) }
      applicable = assertions.select { |assertion| %w[passed failed].include?(assertion[:status]) }
      total = applicable.sum { |assertion| assertion[:weight] }
      earned = applicable.select { |assertion| assertion[:passed] }.sum { |assertion| assertion[:weight] }
      categories = category_scores(applicable)
      score = weighted_score(categories, earned, total)
      critical_failures = assertions.select { |assertion| assertion[:severity] == "critical" && !assertion[:passed] }
      gates = @gates.dup
      gates << { name: "valid_assertions", passed: false } if assertions.any? { |assertion| %w[unsupported error].include?(assertion[:status]) }
      gates << { name: "scorable_assertions", passed: false } if total.zero?
      ids = assertions.map { |assertion| assertion[:id] }
      gates << { name: "unique_assertion_ids", passed: false } unless ids.uniq == ids
      gates << { name: "valid_threshold", passed: false } unless @threshold.finite? && @threshold.between?(0, 100)
      status = if gates.any? { |gate| gate[:passed] != true }
        "blocked"
      elsif critical_failures.any? || score < @threshold
        "failed"
      else
        "passed"
      end
      result = {
        dataset_version: @dataset_version, oracle_version: @oracle_version,
        score:, max_score: 100.0, passed_weight: earned, total_weight: total,
        threshold: @threshold, status:, passed: status == "passed",
        critical_failed: critical_failures.any?, critical_failures: critical_failures.map { |assertion| assertion[:id] },
        assertions:, categories:, gates:
      }
      result[:baseline_diff] = Result::BaselineDiff.compare(current: result, baseline: @baseline) if @baseline
      result
    rescue ArgumentError, TypeError => error
      { dataset_version: @dataset_version, oracle_version: @oracle_version, status: "blocked", passed: false,
        score: nil, assertions: assertions || [], gates: [{ name: "valid_scoring_configuration", passed: false, error: error.message }] }
    end

    private

    def category_scores(assertions)
      assertions.group_by { |assertion| assertion[:category] }.transform_values do |group|
        total = group.sum { |assertion| assertion[:weight] }
        earned = group.select { |assertion| assertion[:passed] }.sum { |assertion| assertion[:weight] }
        { score: total.zero? ? 0.0 : 100.0 * earned / total, passed_weight: earned, total_weight: total }
      end
    end

    def weighted_score(categories, earned, total)
      return (total.zero? ? 0.0 : 100.0 * earned / total).round(4) if @category_weights.empty?

      missing = categories.keys - @category_weights.keys
      raise ArgumentError, "missing category weights: #{missing.join(', ')}" if missing.any?
      weights = @category_weights.transform_values { |value| Float(value) }
      raise ArgumentError, "invalid category weights" unless weights.values.all? { |value| value.finite? && value >= 0 }
      weight = categories.keys.sum { |category| weights.fetch(category) }
      raise ArgumentError, "category weights must have a positive total" unless weight.positive?
      (categories.sum { |category, values| values[:score] * weights.fetch(category) } / weight).round(4)
    end

    Evaluator = self
  end
end
