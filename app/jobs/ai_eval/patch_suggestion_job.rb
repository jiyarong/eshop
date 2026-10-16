module AiEval
  class PatchSuggestionJob < ApplicationJob
    queue_as :default

    def perform(suggestion_id, locale: I18n.default_locale)
      suggestion = PatchSuggestion.find(suggestion_id)
      claimed = suggestion.with_lock do
        next false unless suggestion.status == "queued"
        suggestion.update!(status: "running")
      end
      return unless claimed

      I18n.with_locale(locale) do
        agent = Agent.where(enabled: true, agent_type: :web).find(suggestion.agent_id)
        suggestion.proposal = PatchAssistant.call(documents: suggestion.snapshot.documents,
          instruction: suggestion.instruction, agent: agent).deep_stringify_keys
        candidate = CaseRecord.new(snapshot: suggestion.snapshot, case_key: suggestion.case_key,
          version: suggestion.case_record&.version || 1, definition: suggestion.candidate_definition)
        candidate.materialize
        suggestion.update!(status: "succeeded")
      end
    rescue StandardError => error
      if claimed
        suggestion.update!(status: "failed", proposal: {},
          error: "#{error.class}: #{error.message}".gsub(/Bearer\s+\S+/i, "Bearer [REDACTED]").truncate(2000))
      end
      raise
    end
  end
end
