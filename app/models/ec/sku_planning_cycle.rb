module Ec
  class SkuPlanningCycle < ApplicationRecord
    self.table_name = "ec_sku_planning_cycles"

    STATUSES = %w[pending generating active closed evaluated failed].freeze

    belongs_to :sku, class_name: "Ec::Sku"
    belongs_to :planner_conversation, class_name: "Conversation", optional: true
    has_many :operation_plans, class_name: "Ec::SkuOperationPlan",
      foreign_key: :planning_cycle_id, dependent: :nullify

    validates :period_start, :period_end, :revision, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :revision, numericality: { only_integer: true, greater_than: 0 }
    validate :period_is_monday_and_six_days

    scope :current, -> { where(is_current: true) }
    scope :for_period, ->(period_start) { where(period_start: period_start) }

    enum :status, STATUSES.index_with(&:to_s), validate: true

    def self.current_for(sku:, period_start:)
      find_by(sku: sku, period_start: period_start, is_current: true)
    end

    def cycle
      period_start..period_end
    end

    private

    def period_is_monday_and_six_days
      return if period_start.blank? || period_end.blank?

      errors.add(:period_start, :invalid) unless period_start.monday?
      errors.add(:period_end, :invalid) unless period_end == period_start + 6.days
    end
  end
end
