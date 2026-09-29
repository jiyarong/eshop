module ErpAI
  class SkuPlannerContextBuilder
    DEFAULT_LOOKBACK_PERIODS = 4
    EXTENDED_LOOKBACK_PERIODS = 12
    MAX_PLANS = 24

    def self.call(sku:, period_start: nil, lookback_periods: DEFAULT_LOOKBACK_PERIODS)
      new(sku:, period_start:, lookback_periods:).call
    end

    def initialize(sku:, period_start: nil, lookback_periods: DEFAULT_LOOKBACK_PERIODS)
      @sku = sku
      default_date = Time.current.in_time_zone(Ec::SkuOperationPlan::TIME_ZONE).to_date
      @period_start = (period_start || default_date).to_date.beginning_of_week(:monday)
      @lookback_periods = lookback_periods.to_i.clamp(1, EXTENDED_LOOKBACK_PERIODS)
    end

    def call
      plans = historical_plans
      {
        cycle: {
          start: period_start.iso8601,
          end: (period_start + 6.days).iso8601
        },
        prior_plans: plans.first(MAX_PLANS).map { |plan| serialize_plan(plan) },
        history_plan_ids: plans.first(MAX_PLANS).map(&:id),
        context_version: "sku_planner_v1"
      }
    end

    private

    attr_reader :sku, :period_start, :lookback_periods

    def historical_plans
      plans = sku.sku_operation_plans
        .where("planning_period_end < ?", period_start)
        .includes(:evaluations, :operation_actions)
        .order(planning_period_start: :desc, created_at: :desc, id: :desc)
        .to_a
      return [] if plans.empty?

      recent_periods = plans.map(&:planning_period_start).uniq.first(lookback_periods)
      recent, extended = plans.partition { |plan| recent_periods.include?(plan.planning_period_start) }
      anomalies = extended.select { |plan| anomaly?(plan) }
      (recent + anomalies).sort_by { |plan| [ -plan.planning_period_start.jd, -plan.created_at.to_i, -plan.id ] }
    end

    def anomaly?(plan)
      evaluation = latest_evaluation(plan)
      return true if evaluation.nil? && plan.operation_actions.empty?
      return true if plan.execution_status.in?(%w[not_started partial])

      evaluation && evaluation.effectiveness.in?(%w[negative inconclusive])
    end

    def latest_evaluation(plan)
      plan.evaluations.max_by { |evaluation| [ evaluation.observation_to, evaluation.id ] }
    end

    def serialize_plan(plan)
      evaluation = latest_evaluation(plan)
      {
        plan_id: plan.id,
        cycle: {
          start: plan.planning_period_start.iso8601,
          end: plan.planning_period_end.iso8601
        },
        target: plan.target,
        operation: plan.operation,
        scope: plan.scope,
        scope_id: plan.scope_id,
        message: plan.message,
        reason: plan.reason,
        expected_effect: plan.expected_effect,
        lifecycle_status: plan.lifecycle_status,
        execution_status: plan.execution_status,
        evaluation_status: plan.evaluation_status,
        effectiveness: evaluation&.effectiveness,
        confidence: evaluation&.confidence,
        summary: evaluation&.summary,
        metrics: evaluation&.metrics || {},
        action_ids: plan.operation_actions.map(&:id)
      }
    end
  end
end
