module Ec
  class AISuggestion < ApplicationRecord
    self.table_name = "ec_ai_suggestions"

    STATUSES = {
      pending: "pending",
      running: "running",
      completed: "completed",
      failed: "failed"
    }.freeze
    LISTING_AUDIT_TYPE = "listing_audit".freeze

    belongs_to :suggestable, polymorphic: true
    belongs_to :submitted_by, class_name: "User"
    belongs_to :conversation, optional: true

    enum :status, STATUSES, validate: true

    scope :active, -> { where(status: %w[pending running]) }
    scope :of_type, ->(suggestion_type) { where(suggestion_type: suggestion_type) }
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }

    validates :suggestion_type,
      presence: true,
      format: { with: /\A[a-z0-9]+(?:_[a-z0-9]+)*\z/ }
    validates :content, presence: true, if: :completed?
    validates :error_message, presence: true, if: :failed?

    def active?
      pending? || running?
    end
  end
end
