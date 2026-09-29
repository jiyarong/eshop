require "test_helper"

class Ec::SkuOperationPlanEvaluationRunnerTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @user = User.create!(email: "plan-evaluation-#{@token.downcase}@example.com", password: "password123")
    @sku = Ec::Sku.create!(sku_code: "PLAN-EVAL-#{@token}", product_name: "Plan evaluation")
    @period_start = Date.new(2026, 9, 21)
    @plan = @sku.sku_operation_plans.create!(
      plan_date: @period_start,
      planning_period_start: @period_start,
      planning_period_end: @period_start + 6.days,
      execution_deadline: @period_start + 8.days,
      target: "price",
      operation: "maintain",
      referer: [ "event-#{@token}" ],
      message: "Keep price stable"
    )
  end

  teardown do
    Ec::SkuOperationPlanEvaluation.where(plan_id: @plan&.id).delete_all
    @sku&.sku_operation_plans&.delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "evaluates the previous natural week and is idempotent" do
    provider = ->(_arguments) { { weekly: { after_tax_profit: [ 10, 12 ] } } }
    evaluator = ->(_context) {
      { effectiveness: "positive", confidence: "medium", summary: "Profit improved after the plan." }
    }

    assert_difference "Ec::SkuOperationPlanEvaluation.count", 1 do
      Ec::SkuOperationPlanEvaluationRunner.run(
        as_of_date: Date.new(2026, 9, 29),
        sku_code: @sku.sku_code,
        metrics_provider: provider,
        evaluator: evaluator,
        user: @user
      )
    end

    evaluation = @plan.reload.evaluations.sole
    assert_equal @period_start, evaluation.observation_from
    assert_equal @period_start + 6.days, evaluation.observation_to
    assert_equal "not_started", evaluation.execution_status
    assert_equal "inconclusive", evaluation.effectiveness
    assert_equal "evaluated", @plan.reload.evaluation_status

    assert_no_difference "Ec::SkuOperationPlanEvaluation.count" do
      Ec::SkuOperationPlanEvaluationRunner.run(
        as_of_date: Date.new(2026, 9, 29),
        sku_code: @sku.sku_code,
        metrics_provider: provider,
        evaluator: evaluator,
        user: @user
      )
    end
  end

  test "does not evaluate the current week or use latest as a history filter" do
    current = @sku.sku_operation_plans.create!(
      plan_date: Date.new(2026, 9, 29),
      target: "advertising",
      operation: "maintain",
      referer: [ "event-current-#{@token}" ],
      message: "Keep advertising stable"
    )

    Ec::SkuOperationPlanEvaluationRunner.run(
      as_of_date: Date.new(2026, 9, 29),
      sku_code: @sku.sku_code,
      metrics_provider: ->(_arguments) { {} }
    )

    assert @plan.reload.evaluations.exists?
    assert_empty current.reload.evaluations
  end
end
