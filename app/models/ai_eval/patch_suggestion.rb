module AiEval
  class PatchSuggestion < ApplicationRecord
    self.table_name = "ai_eval_patch_suggestions"

    belongs_to :snapshot, class_name: "AiEval::SnapshotRecord"
    belongs_to :case_record, class_name: "AiEval::CaseRecord", optional: true
    belongs_to :agent
    belongs_to :requested_by, class_name: "User"
    validates :case_key, :instruction, presence: true
    validates :status, inclusion: { in: %w[queued running succeeded failed] }

    def candidate_definition
      definition.merge(proposal.slice("patches", "oracle", "date_mode", "derived_fields"))
    end
  end
end
