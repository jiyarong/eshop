module Ec
  class SkuMarketingState < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_sku_marketing_states"

    GRADES = %w[S A B C].freeze
    STAGES = %w[new grw mat clr].freeze
    STRATEGY_KEYS = {
      [ "S", "new" ] => :full_validation,
      [ "S", "grw" ] => :full_growth,
      [ "S", "mat" ] => :maximize_profit,
      [ "S", "clr" ] => :normally_not_applicable,
      [ "A", "new" ] => :priority_validation,
      [ "A", "grw" ] => :accelerate_growth,
      [ "A", "mat" ] => :stable_operation,
      [ "A", "clr" ] => :controlled_exit,
      [ "B", "new" ] => :validate_demand,
      [ "B", "grw" ] => :assess_growth,
      [ "B", "mat" ] => :low_cost_operation,
      [ "B", "clr" ] => :clearance,
      [ "C", "new" ] => :normally_not_applicable,
      [ "C", "grw" ] => :normally_not_applicable,
      [ "C", "mat" ] => :normally_not_applicable,
      [ "C", "clr" ] => :clearance
    }.freeze

    belongs_to :sku, class_name: "Ec::Sku"
    belongs_to :changed_by, class_name: "User", optional: true

    validates :grade, inclusion: { in: GRADES }
    validates :stage, inclusion: { in: STAGES }
    validates :effective_at, presence: true
    validate :ended_at_not_before_effective_at

    before_validation do
      self.grade = grade.to_s.upcase.presence
      self.stage = stage.to_s.downcase.presence
    end

    scope :current, -> { where(ended_at: nil) }
    scope :at, ->(time) { where("effective_at <= ? AND (ended_at IS NULL OR ended_at > ?)", time, time) }
    scope :recent_first, -> { order(effective_at: :desc, id: :desc) }

    def strategy_key
      STRATEGY_KEYS[[ grade, stage ]]
    end

    def exceptional_combination?
      strategy_key == :normally_not_applicable
    end

    private

    def ended_at_not_before_effective_at
      return if effective_at.blank? || ended_at.blank? || ended_at >= effective_at

      errors.add(:ended_at, :before_effective_at)
    end
  end
end
