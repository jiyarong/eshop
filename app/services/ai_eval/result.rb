# frozen_string_literal: true

module AiEval
  module Result
    class BaselineDiff
      def self.compare(current:, baseline:)
        new(current:, baseline:).call
      end

      def initialize(current:, baseline:)
        @current = current.to_h.deep_stringify_keys
        @baseline = baseline.to_h.deep_stringify_keys
      end

      def call
        versions = %w[dataset_version oracle_version]
        mismatch = versions.select { |key| @current[key].blank? || @baseline[key].blank? || @current[key] != @baseline[key] }
        return { comparable: false, reason: "version_mismatch", mismatched_versions: mismatch } if mismatch.any?

        current = @current.fetch("assertions", []).index_by { |item| item.fetch("id") }
        baseline = @baseline.fetch("assertions", []).index_by { |item| item.fetch("id") }
        shared_ids = current.keys & baseline.keys
        newly_failed = shared_ids.select { |id| passed?(baseline[id]) && !passed?(current[id]) }
        newly_passed = shared_ids.select { |id| !passed?(baseline[id]) && passed?(current[id]) }
        critical = newly_failed.select { |id| current[id]["severity"] == "critical" }
        {
          score_delta: (@current.fetch("score", 0).to_f - @baseline.fetch("score", 0).to_f).round(4),
          status_changed: @current["status"] != @baseline["status"],
          newly_failed:, newly_passed:, critical_regressions: critical,
          added: current.keys - baseline.keys,
          removed: baseline.keys - current.keys,
          comparable: current.keys.sort == baseline.keys.sort,
          regression: newly_failed.any? || critical.any?
        }
      end

      private

      def passed?(assertion)
        assertion["passed"] == true && assertion["status"] == "passed"
      end
    end
  end
end
