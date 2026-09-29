require "test_helper"

class ErpAI::SkuPlannerContextBuilderTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "PLAN-CONTEXT-#{@token}", product_name: "Plan context")
    @current_period = Date.new(2026, 9, 28)
  end

  teardown do
    Ec::SkuOperationPlanEvaluation.where(plan_id: @sku&.sku_operation_plans&.select(:id)).delete_all
    @sku&.sku_operation_plans&.delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "returns recent plans and older negative plans with evaluation details" do
    recent = create_plan(Date.new(2026, 9, 21), target: "price")
    old = create_plan(Date.new(2026, 8, 24), target: "advertising")
    old.evaluations.create!(
      observation_from: old.planning_period_start,
      observation_to: old.planning_period_end,
      execution_status: "executed",
      effectiveness: "negative",
      confidence: "medium",
      summary: "The result deteriorated.",
      metrics: { "profit" => { "before" => 10, "after" => 5 } },
      evidence: {},
      action_ids: [],
      evaluator_version: "test",
      status: "succeeded"
    )

    context = ErpAI::SkuPlannerContextBuilder.call(
      sku: @sku,
      period_start: @current_period,
      lookback_periods: 1
    )

    assert_equal @current_period.iso8601, context.fetch(:cycle).fetch(:start)
    assert_equal [ recent.id, old.id ], context.fetch(:history_plan_ids)
    assert_equal "negative", context.fetch(:prior_plans).last.fetch(:effectiveness)
    assert_equal "medium", context.fetch(:prior_plans).last.fetch(:confidence)
    assert_equal({ "profit" => { "before" => 10, "after" => 5 } }, context.fetch(:prior_plans).last.fetch(:metrics))
  end

  private

  def create_plan(period_start, target:)
    @sku.sku_operation_plans.create!(
      plan_date: period_start,
      planning_period_start: period_start,
      planning_period_end: period_start + 6.days,
      execution_deadline: period_start + 8.days,
      target: target,
      operation: "maintain",
      referer: [ "event-#{period_start}" ],
      message: "Plan #{target}"
    )
  end
end
