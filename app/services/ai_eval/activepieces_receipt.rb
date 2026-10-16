module AiEval
  class ActivepiecesReceipt
    def self.call(run:, external_run_id:, payload:)
      run.with_lock do
        raise ArgumentError, I18n.t("ai_eval.errors.not_awaiting_flow") unless run.status == "awaiting_activepieces"
        raise ArgumentError, I18n.t("ai_eval.errors.invalid_receipt") unless payload.is_a?(Hash)
        value = payload.deep_stringify_keys
        metadata = value["metadata"]
        raise ArgumentError, I18n.t("ai_eval.errors.invalid_receipt") unless metadata.is_a?(Hash)
        expected = run.trace.fetch("materialization")
        valid = external_run_id.present? && metadata["external_run_id"] == external_run_id &&
          metadata["run_id"].to_s == run.id.to_s &&
          %w[fingerprint sku_code as_of time_zone].all? { |key| metadata[key] == expected[key] } &&
          value["output"].is_a?(Hash) && value["execution_status"] == "SUCCEEDED"
        raise ArgumentError, I18n.t("ai_eval.errors.invalid_receipt") unless valid
        run.update!(outputs: run.outputs.merge("activepieces" => value.fetch("output")),
          trace: run.trace.merge("activepieces" => {
            status: "completed", external_run_id: external_run_id, source: "manual_import",
            metadata: metadata, steps: value.fetch("steps", []),
            gates: [{ name: "matching_materialization", passed: true }]
          }))
        RunExecutor.score!(run)
      end
      run
    end
  end
end
