module Ec
  class SkuOperationPlan < ApplicationRecord
    require "digest"

    self.table_name = "ec_ai_sku_operation_plans"
    TIME_ZONE = "Asia/Shanghai".freeze
    EXECUTION_GRACE_DAYS = 1

    TARGET_ALIASES = {
      "价格" => "price",
      "广告" => "advertising",
      "listing属性" => "listing_attribute",
      "listing图" => "listing_image",
      "分仓" => "warehouse_distribution",
      "补货" => "replenishment"
    }.freeze
    OPERATION_ALIASES = {
      "增加" => "increase",
      "降低" => "decrease",
      "打开" => "open",
      "关闭" => "close",
      "修改" => "modify",
      "维持" => "maintain"
    }.freeze
    TARGET_SCOPES = {
      "price" => %w[LISTING],
      "advertising" => %w[LISTING],
      "listing_attribute" => %w[LISTING],
      "listing_image" => %w[LISTING],
      "warehouse_distribution" => %w[LISTING],
      "replenishment" => %w[SKU]
    }.freeze

    belongs_to :sku, class_name: "Ec::Sku"
    belongs_to :planning_cycle, class_name: "Ec::SkuPlanningCycle", optional: true
    belongs_to :conversation, optional: true
    has_many :operation_actions, class_name: "Ec::OperationAction", foreign_key: :plan_id, dependent: :nullify
    has_many :evaluations, class_name: "Ec::SkuOperationPlanEvaluation", foreign_key: :plan_id, dependent: :destroy

    enum :status, { active: "active", done: "done", ignored: "ignored" }, validate: true
    enum :lifecycle_status, { active: "active", cancelled: "cancelled", expired: "expired" }, prefix: true, validate: true
    enum :execution_status, { not_started: "not_started", partial: "partial", executed: "executed", not_applicable: "not_applicable" }, prefix: true, validate: true
    enum :evaluation_status, { pending: "pending", insufficient_data: "insufficient_data", evaluated: "evaluated", failed: "failed" }, prefix: true, validate: true
    enum :target, {
      price: "price",
      advertising: "advertising",
      listing_attribute: "listing_attribute",
      listing_image: "listing_image",
      warehouse_distribution: "warehouse_distribution",
      replenishment: "replenishment"
    }, validate: true
    enum :operation, {
      increase: "increase",
      decrease: "decrease",
      open: "open",
      close: "close",
      modify: "modify",
      maintain: "maintain"
    }, validate: true

    before_validation :set_plan_date, on: :create
    before_validation :set_planning_period, on: :create
    before_validation :set_execution_deadline, on: :create
    before_validation :set_retain_until, on: :create
    before_validation :set_completed_at
    before_validation :normalize_plan_values
    before_validation :set_fingerprint, on: :create
    before_validation :sync_status_dimensions

    validates :message, :retain_until, :plan_date, :planning_period_start, :planning_period_end, :execution_deadline, presence: true
    validate :referer_must_be_present
    validate :scope_matches_target
    validate :scope_id_matches_scope

    scope :retained, -> { where("retain_until > ?", Time.current) }
    scope :latest, -> { where(is_latest: true) }
    scope :for_period, ->(period_start) { where(planning_period_start: period_start) }
    scope :before_period, ->(period_start) { where("planning_period_start < ?", period_start) }

    def self.period_for(date)
      date.to_date.beginning_of_week(:monday)
    end

    def self.period_end_for(date)
      period_for(date) + 6.days
    end

    def self.execution_deadline_for(date)
      period_end_for(date) + EXECUTION_GRACE_DAYS.days
    end

    def self.allowed_scopes_for_target(target)
      TARGET_SCOPES[target.to_s]
    end

    def self.fingerprint_for(attributes)
      values = attributes.stringify_keys
      Digest::SHA256.hexdigest(
        {
          target: values["target"].to_s,
          operation: values["operation"].to_s,
          scope: values["scope"].to_s,
          scope_id: values["scope_id"].to_s,
          planning_period_start: values["planning_period_start"]&.to_date&.iso8601
        }.to_json
      )
    end

    def cycle
      planning_period_start..planning_period_end
    end

    def period_start
      planning_period_start
    end

    def period_end
      planning_period_end
    end

    def latest_evaluation
      return evaluations.max_by { |evaluation| [ evaluation.observation_to, evaluation.id ] } if evaluations.loaded?

      evaluations.order(observation_to: :desc, id: :desc).first
    end

    def action_matchable_at?(time)
      date = time.in_time_zone(TIME_ZONE).to_date
      lifecycle_status == "active" && planning_period_start <= date && execution_deadline >= date
    end

    def self.referenced_events_by_sku_id(plans)
      plan_list = Array(plans)
      event_ids = plan_list.flat_map(&:referer).filter_map do |reference|
        Integer(reference, exception: false) if reference.is_a?(String) || reference.is_a?(Integer)
      end.select(&:positive?).uniq
      return {} if event_ids.empty?

      Ec::AIDiagnosisEvent.joins(:ai_diagnosis)
        .where(id: event_ids, ec_ai_diagnosis: { sku_id: plan_list.map(&:sku_id) })
        .includes(:ai_diagnosis)
        .group_by { |event| event.ai_diagnosis.sku_id }
        .transform_values { |events| events.index_by(&:id) }
    end

    private

    def set_retain_until
      return if retain_until.present?

      zone = Time.find_zone!(TIME_ZONE)
      self.retain_until = zone.local(
        execution_deadline.year,
        execution_deadline.month,
        execution_deadline.day
      ).end_of_day
    end

    def set_plan_date
      self.plan_date ||= Time.current.in_time_zone(TIME_ZONE).to_date
    end

    def set_planning_period
      self.planning_period_start ||= self.class.period_for(plan_date)
      self.planning_period_end ||= planning_period_start + 6.days
    end

    def set_execution_deadline
      self.execution_deadline ||= planning_period_end + EXECUTION_GRACE_DAYS.days
    end

    def normalize_plan_values
      self.target = TARGET_ALIASES.fetch(target.to_s, target) if target.present?
      self.operation = OPERATION_ALIASES.fetch(operation.to_s, operation) if operation.present?
    end

    def sync_status_dimensions
      self.lifecycle_status = "cancelled" if status.to_s == "ignored"
      self.execution_status = "executed" if status.to_s == "done"
      self.execution_status = "not_applicable" if lifecycle_status.to_s == "cancelled"
    end

    def set_completed_at
      return unless will_save_change_to_status? && status.in?(%w[done ignored])

      self.completed_at ||= Time.current
    end

    def referer_must_be_present
      self.referer = Array(referer).filter_map do |reference|
        value = reference.is_a?(String) ? reference.strip : reference
        value if value.present?
      end.uniq
      errors.add(:referer, :blank) if referer.empty?
    end

    def scope_matches_target
      return if persisted? && !will_save_change_to_target? && !will_save_change_to_scope?
      return if target.blank? || scope.blank?

      allowed_scopes = self.class.allowed_scopes_for_target(target)
      return if allowed_scopes&.include?(scope.to_s)

      errors.add(:scope, :invalid)
    end

    def scope_id_matches_scope
      return if persisted? && !will_save_change_to_target? && !will_save_change_to_scope? && !will_save_change_to_scope_id?
      return if scope.blank?

      if scope_id.blank?
        errors.add(:scope_id, :blank)
        return
      end

      case scope.to_s
      when "SKU"
        errors.add(:scope_id, :invalid) unless scope_id.to_s == sku&.sku_code.to_s
      when "LISTING"
        listing_id = Integer(scope_id, exception: false)
        valid_listing = listing_id&.positive? && sku&.sku_products&.exists?(id: listing_id)
        errors.add(:scope_id, :invalid) unless valid_listing
      end
    end

    def set_fingerprint
      return if fingerprint.present?

      self.fingerprint = self.class.fingerprint_for(
        target: target,
        operation: operation,
        scope: scope,
        scope_id: scope_id,
        planning_period_start: planning_period_start
      )
    end
  end
end
