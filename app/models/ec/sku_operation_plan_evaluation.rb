module Ec
  class SkuOperationPlanEvaluation < ApplicationRecord
    self.table_name = "ec_ai_sku_operation_plan_evaluations"

    EXECUTION_STATUSES = %w[not_started partial executed not_applicable].freeze
    EFFECTIVENESS_VALUES = %w[positive negative mixed inconclusive].freeze
    CONFIDENCE_VALUES = %w[high medium low].freeze
    STATUSES = %w[pending running succeeded failed].freeze

    belongs_to :plan, class_name: "Ec::SkuOperationPlan"
    belongs_to :conversation, optional: true

    enum :execution_status, EXECUTION_STATUSES.index_with(&:itself), prefix: true, validate: true
    enum :effectiveness, EFFECTIVENESS_VALUES.index_with(&:itself), prefix: true, validate: true
    enum :confidence, CONFIDENCE_VALUES.index_with(&:itself), prefix: true, validate: true
    enum :status, STATUSES.index_with(&:itself), prefix: true, validate: true

    validates :observation_from, :observation_to, :status, presence: true
    validates :execution_status, :effectiveness, :confidence, :summary, :evaluator_version,
      presence: true, if: :completed?
    validates :observation_to, comparison: { greater_than_or_equal_to: :observation_from }
    validate :json_fields_are_objects

    scope :successful, -> { where(status: "succeeded") }
    scope :latest_first, -> { order(observation_to: :desc, id: :desc) }

    def completed?
      status.in?(%w[succeeded failed])
    end

    private

    def json_fields_are_objects
      errors.add(:metrics, :invalid) unless metrics.is_a?(Hash)
      errors.add(:evidence, :invalid) unless evidence.is_a?(Hash)
      errors.add(:action_ids, :invalid) unless action_ids.is_a?(Array)
    end
  end
end
