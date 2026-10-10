require "test_helper"

class Ec::SkuOperationPlanEvaluationRunnerTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @user = User.create!(email: "plan-evaluation-#{@token.downcase}@example.com", password: "password123")
    @sku = Ec::Sku.create!(sku_code: "PLAN-EVAL-#{@token}", product_name: "Plan evaluation")
    @store = Ec::Store.create!(platform: "wb", store_name: "Evaluation #{@token}", company_type: "small")
    @product = @sku.sku_products.create!(store: @store, product_id: @token)
    @agent_existed = Agent.exists?(code: "sku_plan_evaluation")
    @agent_settings = Agent.find_by(code: "sku_plan_evaluation")&.attributes&.slice("model_id", "thinking_enabled", "thinking_level")
    @period_start = Date.new(2026, 9, 21)
    @diagnosis_rules = []
    @plan = @sku.sku_operation_plans.create!(
      plan_date: @period_start,
      planning_period_start: @period_start,
      planning_period_end: @period_start + 6.days,
      execution_deadline: @period_start + 7.days,
      target: "price",
      operation: "maintain",
      referer: [ "event-#{@token}" ],
      message: "Keep price stable"
    )
  end

  teardown do
    Ec::SkuOperationPlanEvaluation.where(plan_id: @plan&.id).delete_all
    Ec::OperationAction.where(ec_sku_id: @sku.id).delete_all
    @sku&.sku_operation_plans&.delete_all
    @sku.planning_cycles.delete_all
    Ec::AIDiagnosis.where(sku_id: @sku&.id).destroy_all
    Ec::SkuDiagnosisRule.where(id: @diagnosis_rules.map(&:id)).delete_all
    Message.where(conversation: Conversation.where(user: @user)).delete_all
    Conversation.where(user: @user).delete_all
    Agent.where(code: "sku_plan_evaluation").delete_all unless @agent_existed
    Agent.find_by!(code: "sku_plan_evaluation").update!(@agent_settings) if @agent_existed
    @product.delete
    @store.delete
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
    assert_equal @period_start + 7.days, evaluation.observation_to
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

  test "calls the Evaluation Agent with grace-day evidence and saves its conversation once" do
    cycle = Ec::SkuPlanningCycleLock.acquire(sku: @sku, period_start: @period_start, status: "active")
    @plan.update!(planning_cycle: cycle)
    action = create_action(on: @period_start + 7.days)
    other_action = create_action(on: @period_start + 6.days, plan: nil)
    requests = []
    client = Object.new
    client.define_singleton_method(:complete) do |request|
      requests << request
      { content: { effectiveness: "positive", confidence: "medium", summary: "Profit increased with limited evidence." } }
    end
    agent = Agent.ensure_fixed!("sku_plan_evaluation")
    agent.update!(model_id: "deepseek-v4-flash", thinking_enabled: true, thinking_level: "max")
    arguments = evaluation_arguments.merge(client: client, agent: agent)

    evaluation = Ec::SkuOperationPlanEvaluationRunner.run(**arguments).sole
    assert_equal "succeeded", evaluation.status
    assert_equal true, requests.sole.fetch(:thinking_enabled)
    assert_equal "max", requests.sole.fetch(:thinking_level)
    assert_equal [action.id], evaluation.action_ids
    assert_equal action.id, evaluation.evidence.fetch("actions").sole.fetch("id")
    assert_equal metrics.deep_stringify_keys, evaluation.metrics
    assert_equal "sku_plan_evaluation_v2", evaluation.evaluator_version
    assert_equal "sku_plan_evaluation", evaluation.conversation.module_name
    assert_equal @plan.id.to_s, evaluation.conversation.business_object_id
    assert_equal %w[user assistant], evaluation.conversation.messages.order(:id).pluck(:role)
    payload = JSON.parse(requests.sole.fetch(:messages).sole.fetch(:content))
    assert_equal [other_action.id], payload.fetch("concurrent_actions").map { |row| row.fetch("id") }
    assert_equal (@period_start + 7.days).iso8601, payload.fetch("observation_to")
    assert_equal "expired", @plan.reload.lifecycle_status
    assert_equal "evaluated", cycle.reload.status

    Ec::SkuOperationPlanEvaluationRunner.run(**arguments)
    assert_equal 1, requests.size
    assert_equal 1, @plan.evaluations.count
  end

  test "passes current and previous week diagnosis context and fetches metrics" do
    rule = Ec::SkuDiagnosisRule.create!(name: "Evaluation rule #{@token}", prompt: "Check the event")
    @diagnosis_rules << rule
    previous_diagnosis = Ec::GeneralDiagnosis.create!(
      sku: @sku, submitted_by: @user, data: {}, created_at: @period_start + 1.day
    )
    previous_event = previous_diagnosis.events.create!(
      sub_agent: rule, event_type: "stock_risk", severity: "warning",
      message: "Previous stock risk", details: { quantity: 0 },
      created_at: @period_start + 1.day
    )
    current_start = @period_start + 1.week
    current_diagnosis = Ec::GeneralDiagnosis.create!(
      sku: @sku, submitted_by: @user, data: {}, created_at: current_start + 1.day
    )
    current_diagnosis.events.create!(
      sub_agent: rule, event_type: "stock_risk", severity: "info",
      simple_context: "current evidence", message: "Stock risk improved",
      created_at: current_start + 1.day
    )
    current_diagnosis.events.create!(
      event_type: "old_advice", severity: "critical", scope: "advise",
      simple_context: "should be excluded", message: "Advice"
    )
    create_action(on: @period_start + 7.days)

    requests = []
    client = Object.new
    client.define_singleton_method(:complete) do |request|
      requests << request
      { content: { effectiveness: "positive", confidence: "medium", summary: "The diagnosis improved." } }
    end
    metrics_query = Class.new do
      class << self
        attr_accessor :calls
      end

      def initialize(*)
        self.class.calls += 1
      end

      def call
        {}
      end
    end
    metrics_query.calls = 0
    agent = Agent.ensure_fixed!("sku_plan_evaluation")

    evaluation = Ec::SkuOperationPlanEvaluationRunner.new(
      **evaluation_arguments.except(:metrics_provider).merge(client: client, agent: agent, metrics_query_class: metrics_query)
    ).run.sole

    payload = JSON.parse(requests.sole.fetch(:messages).sole.fetch(:content))
    diagnosis_context = payload.fetch("diagnosis_context")
    assert_equal current_start.iso8601, diagnosis_context.fetch("current_week").fetch("from")
    assert_equal @period_start.iso8601, diagnosis_context.fetch("previous_week").fetch("from")
    assert_includes diagnosis_context.dig("previous_week", "events", 0, "simple_context"), "Previous stock risk"
    assert_includes diagnosis_context.dig("previous_week", "events", 0, "simple_context"), '"quantity":0'
    assert_nil previous_event.reload.simple_context
    assert_equal "Previous stock risk", diagnosis_context.dig("previous_week", "events", 0, "message")
    assert_equal "current evidence", diagnosis_context.dig("current_week", "events", 0, "simple_context")
    assert_equal "Stock risk improved", diagnosis_context.dig("current_week", "events", 0, "message")
    assert_equal 1, diagnosis_context.fetch("current_week").fetch("events").size
    assert_equal 1, metrics_query.calls
    assert_equal({}, evaluation.metrics)
    assert_equal diagnosis_context.deep_stringify_keys, evaluation.evidence.fetch("diagnosis_context")
  end

  test "retains metrics, action evidence and conversation on AI failure and retries the same row" do
    action = create_action(on: @period_start + 7.days)
    agent = Agent.ensure_fixed!("sku_plan_evaluation")
    client = Object.new
    client.define_singleton_method(:complete) { |_| raise "AI unavailable" }
    failed = Ec::SkuOperationPlanEvaluationRunner.run(**evaluation_arguments, client: client, agent: agent).sole
    assert_equal "failed", failed.status
    assert_equal "failed", @plan.reload.evaluation_status
    assert_equal [action.id], failed.action_ids
    assert_equal metrics.deep_stringify_keys, failed.metrics
    assert failed.conversation_id.present?

    client.define_singleton_method(:complete) { |_| { content: { effectiveness: "mixed", confidence: "low", summary: "Mixed evidence" } } }
    retried = Ec::SkuOperationPlanEvaluationRunner.run(**evaluation_arguments, client: client, agent: agent).sole
    assert_equal failed.id, retried.id
    assert_equal "succeeded", retried.status
    assert_equal "mixed", retried.effectiveness
  end

  test "does not call AI for unavailable profit or plans without execution" do
    evaluator = ->(_) { flunk "AI should not infer effectiveness from missing evidence" }
    Ec::SkuOperationPlanEvaluationRunner.run(**evaluation_arguments, evaluator: evaluator)
    create_action(on: @period_start + 7.days)
    evaluation = Ec::SkuOperationPlanEvaluationRunner.run(**evaluation_arguments.merge(
      metrics_provider: ->(_) { { weekly_profit_by_week_and_store: { "week" => { after_tax_profit: nil } } } },
      evaluator: evaluator, force: true)).sole
    assert_equal "inconclusive", evaluation.effectiveness
    assert_equal "insufficient_data", @plan.reload.evaluation_status
  end

  test "a legacy done flag without observed actions cannot override not started" do
    @plan.update!(status: "done")
    evaluation = Ec::SkuOperationPlanEvaluationRunner.run(**evaluation_arguments).sole
    assert_equal "not_started", evaluation.execution_status
    assert_equal "not_started", @plan.reload.execution_status
    assert_equal "inconclusive", evaluation.effectiveness
  end

  test "open historical deadlines are deferred and caught up after the complete window" do
    @plan.update!(execution_deadline: @period_start + 8.days)
    assert_empty Ec::SkuOperationPlanEvaluationRunner.run(**evaluation_arguments)
    create_action(on: @period_start + 8.days)
    result = Ec::SkuOperationPlanEvaluationRunner.run(**evaluation_arguments.merge(as_of_date: Date.new(2026, 10, 6))).sole
    assert_equal @period_start + 8.days, result.observation_to
    assert_equal 1, result.action_ids.size
  end

  test "manual early evaluation limits both metrics and actions to the last complete day" do
    included = create_action(on: @period_start + 2.days)
    create_action(on: @period_start + 3.days)
    queried_to = nil
    provider = ->(args) { queried_to = args.fetch(:to_date); metrics }
    result = Ec::SkuOperationPlanEvaluationRunner.run(**evaluation_arguments.merge(
      as_of_date: @period_start + 3.days, plan_id: @plan.id, metrics_provider: provider)).sole
    assert_equal @period_start + 2.days, queried_to
    assert_equal queried_to, result.observation_to
    assert_equal [included.id], result.action_ids
    assert_equal "active", @plan.reload.lifecycle_status
    final = Ec::SkuOperationPlanEvaluationRunner.run(**evaluation_arguments).sole
    assert_equal @plan.execution_deadline, final.observation_to
    assert_equal 2, final.action_ids.size
    assert_equal 2, @plan.evaluations.count
  end

  private

  def metrics
    { before: { after_tax_profit: 10 }, after: { after_tax_profit: 12 } }
  end

  def evaluation_arguments
    { as_of_date: Date.new(2026, 9, 29), sku_code: @sku.sku_code,
      metrics_provider: ->(_) { metrics }, user: @user }
  end

  def create_action(on:, plan: @plan)
    zone = Time.find_zone!(Ec::SkuOperationPlan::TIME_ZONE)
    Ec::OperationAction.create!(sku: @sku, sku_product: @product, store: @store, operated_by_user: @user,
      operated_at: zone.local(on.year, on.month, on.day, 23), operation_type: "listing_pricing",
      plan: plan, diff_result: { fields: { price: { from: 100, to: 120 } } })
  end
end
