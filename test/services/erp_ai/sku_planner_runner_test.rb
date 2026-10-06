require "test_helper"

class ErpAI::SkuPlannerRunnerTest < ActiveSupport::TestCase
  setup do
    travel_to Time.utc(2026, 9, 29, 4)
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "PLANNER-#{@token}", product_name: "Planner test")
    @user = User.create!(email: "planner-#{@token.downcase}@example.com", password: "password123")
    @agent_existed = Agent.exists?(code: "sku_planner")
    @evaluation_agent_existed = Agent.exists?(code: "sku_plan_evaluation")
    @rules = []
    @rule = create_rule(frequency: "weekly")
    @diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user)
    @diagnosis.events.create!(sub_agent: @rule, event_type: "stock_risk", severity: "warning", message: "Stock is low")
  end

  teardown do
    Ec::OperationAction.where(ec_sku_id: @sku.id).delete_all
    Ec::SkuOperationPlanEvaluation.where(plan_id: @sku.sku_operation_plans.select(:id)).delete_all
    @sku.sku_operation_plans.delete_all
    @sku.planning_cycles.delete_all
    @sku.ai_diagnoses.destroy_all
    @rules.each(&:delete)
    Message.where(conversation: Conversation.where(user: @user)).delete_all
    Conversation.where(user: @user).delete_all
    Agent.where(code: "sku_planner").delete_all unless @agent_existed
    Agent.where(code: "sku_plan_evaluation").delete_all unless @evaluation_agent_existed
    @sku.sku_products.delete_all
    @evaluation_store&.delete
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    UserRole.where(user_id: @user.id).delete_all
    User.where(id: @user.id).delete_all
    travel_back
  end

  test "same-day rerun preserves the previous revision and makes it non-latest" do
    today = Time.current.in_time_zone("Asia/Shanghai").to_date
    previous = create_plan("Previous", plan_date: today - 1.day)
    replaced = create_plan("Replaced", created_at: 1.day.ago, plan_date: today)

    run_with_plan("First")
    assert Ec::SkuOperationPlan.exists?(replaced.id)
    assert_equal [ "First" ], @sku.sku_operation_plans.latest.pluck(:message)
    assert_not previous.reload.is_latest?

    run_with_plan("Second")
    assert_equal [ "Second" ], @sku.sku_operation_plans.latest.pluck(:message)
    assert_equal 4, @sku.sku_operation_plans.count
  end

  test "failed run restores deleted plans and discards partially generated plans" do
    previous = create_plan("Previous", created_at: 1.day.ago)
    existing = create_plan("Existing")

    run_with_plan("Partial", fail_after_save: true)

    assert_equal [ "Previous", "Existing" ], @sku.sku_operation_plans.order(:created_at).pluck(:message)
    assert previous.reload.is_latest?
    assert existing.reload.is_latest?
  end

  test "planner context excludes info events and treats severity as supporting evidence" do
    @diagnosis.events.create!(sub_agent: create_rule, event_type: "routine_check", severity: "info", message: "No action needed")
    @diagnosis.events.create!(sub_agent: create_rule, event_type: "urgent_stock", severity: "critical", message: "Immediate action")
    captured = nil
    fake_runner = Object.new
    fake_runner.define_singleton_method(:ask) { |**args| captured = args; nil }

    ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user,
      runner_factory: ->(**_args) { fake_runner }).run

    events = JSON.parse(captured.fetch(:data_summary))
    assert_equal %w[stock_risk urgent_stock], events.map { |event| event.fetch("event_type") }
    assert_equal @diagnosis.events.where.not(severity: "info").order(:position, :id).pluck(:id), events.map { |event| event.fetch("id") }
    assert_includes captured.fetch(:question), "非 info 通用诊断事件"
    assert_includes captured.fetch(:question), "warning 和 critical 表示诊断紧迫程度，仅供经营判断参考"
    assert_includes captured.fetch(:question), "没有足够依据时不调用 save_sku_plan"
  end

  test "planner uses current weekly and daily rule events across diagnosis dates and accepts their references" do
    @user.roles << Role.find_by!(code: "manager")
    weekly = @diagnosis.events.sole
    weekly.update!(details: { quantity: 0 })
    date = Date.new(2026, 9, 30)
    daily_diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user,
      created_at: Time.find_zone!("Asia/Shanghai").local(2026, 9, 30, 3))
    daily = daily_diagnosis.events.create!(sub_agent: create_rule, event_type: "sales_drop",
      severity: "warning", message: "Sales fell", simple_context: "Current sales evidence")
    daily_diagnosis.events.create!(event_type: "legacy_joint", severity: "critical", message: "Old joint diagnosis")
    daily_diagnosis.events.create!(scope: "advise", event_type: "advice", severity: "critical", message: "Old advice")
    stale_diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user,
      created_at: Time.find_zone!("Asia/Shanghai").local(2026, 9, 27, 23, 59))
    stale = stale_diagnosis.events.create!(sub_agent: create_rule, event_type: "stale_risk", severity: "critical", message: "Previous week")
    future_diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user,
      created_at: Time.find_zone!("Asia/Shanghai").local(2026, 10, 1))
    future_diagnosis.events.create!(sub_agent: create_rule, event_type: "future_risk", severity: "critical", message: "Future")
    captured = nil
    fake_runner = Object.new
    fake_runner.define_singleton_method(:ask) { |**args| captured = args; nil }

    ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user, as_of_date: date,
      runner_factory: ->(**) { fake_runner }).run

    events = JSON.parse(captured.fetch(:data_summary))
    assert_equal [ weekly.id, daily.id ], events.map { |event| event.fetch("id") }
    assert_includes events.first.fetch("simple_context"), weekly.message
    assert_includes events.first.fetch("simple_context"), '"quantity":0'
    assert_equal "Current sales evidence", events.last.fetch("simple_context")
    assert_nil weekly.reload.simple_context
    assert_not @diagnosis.reload.is_latest?
    enabled_for = Ec::SkuDiagnosisRule.method(:enabled_for)
    rule_ids = [ @rule.id, daily.sub_agent_id ]
    with_stubbed_singleton_method(Ec::SkuDiagnosisRule, :enabled_for, ->(on) { enabled_for.call(on).where(id: rule_ids) }) do
      assert AITasks::SkuPlanningPipelineJob.diagnosis_complete?(as_of_date: date, sku_code: @sku.sku_code)
    end

    executor = ErpAI::SkuPlannerRunner::ScopedToolExecutor.new(user: @user, sku: @sku, plan_date: date)
    arguments = { sku_code: @sku.sku_code, target: "price", operation: "maintain", **plan_details }
    result = executor.call(id: "save", name: "save_sku_plan", arguments: arguments.merge(referer: [ weekly.id, daily.id ]))
    assert result.dig(:result, :success)
    assert_raises(RuntimeError) do
      executor.call(id: "stale", name: "save_sku_plan", arguments: arguments.merge(referer: [ stale.id ]))
    end
  end

  test "planner skips legacy joint diagnoses without a rule" do
    @diagnosis.events.delete_all
    @diagnosis.events.create!(event_type: "legacy_joint", severity: "warning", message: "Old joint diagnosis")

    result = ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user,
      runner_factory: ->(**) { flunk "Legacy joint diagnosis must not generate a new plan" }).run

    assert_empty result
    assert_equal 1, @diagnosis.events.count
  end

  test "planner sends the saved database prompt to the model" do
    agent = Agent.ensure_fixed!("sku_planner")
    original_prompt = agent.system_prompt
    agent.update!(system_prompt: "数据库中的 SKU Planner 提示词")
    request = nil
    client = Object.new
    client.define_singleton_method(:complete) do |value|
      request = value
      { content: "本周期不生成计划", tool_calls: [] }
    end

    conversation = ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user, client: client).run.first

    assert_equal "数据库中的 SKU Planner 提示词", request.fetch(:system_prompt)
    assert_equal "数据库中的 SKU Planner 提示词", conversation.context.fetch("system_prompt")
    assert_equal "数据库中的 SKU Planner 提示词", agent.reload.system_prompt
  ensure
    agent&.update_columns(system_prompt: original_prompt) if @agent_existed
  end

  test "planner skips SKUs with only info events" do
    @diagnosis.events.delete_all
    @diagnosis.events.create!(sub_agent: @rule, event_type: "routine_check", severity: "info", message: "No action needed")
    existing = create_plan("Existing")

    result = ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user,
      runner_factory: ->(**_args) { flunk "Planner should not run for info-only events" }).run

    assert_empty result
    assert existing.reload.is_latest?
  end

  test "automatic retry reuses the cycle and manual rerun creates a new revision" do
    client = Object.new
    calls = 0
    client.define_singleton_method(:complete) { |**| calls += 1; { content: "No plan needed", tool_calls: [] } }
    client.define_singleton_method(:complete) { |_| calls += 1; { content: "No plan needed", tool_calls: [] } }
    arguments = { sku_code: @sku.sku_code, user: @user, client: client, as_of_date: Date.new(2026, 9, 29) }

    first = ErpAI::SkuPlannerRunner.run(**arguments, rerun: false).sole
    second = ErpAI::SkuPlannerRunner.run(**arguments, rerun: false).sole
    assert_equal first.id, second.id
    assert_equal 1, calls
    assert_equal [1], @sku.planning_cycles.pluck(:revision)

    ErpAI::SkuPlannerRunner.run(**arguments, rerun: true)
    assert_equal 2, calls
    assert_equal [1, 2], @sku.planning_cycles.order(:revision).pluck(:revision)
  end

  test "automatic planner failure is retryable without leaving partial plans" do
    failed_runner = Object.new
    failed_runner.define_singleton_method(:ask) { |**| raise "model unavailable" }
    assert_raises(ErpAI::SkuPlannerRunner::Failure) do
      ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user, rerun: false,
        runner_factory: ->(**) { failed_runner }).run
    end
    assert_empty @sku.planning_cycles
    assert_empty @sku.sku_operation_plans
  end

  test "direct planner evaluates history before building context and does not repeat successful evaluation" do
    previous = historical_plan
    @evaluation_store = Ec::Store.create!(platform: "wb", store_name: "Planner evaluation #{@token}", company_type: "small")
    product = @sku.sku_products.create!(store: @evaluation_store, product_id: @token)
    Ec::OperationAction.create!(sku: @sku, sku_product: product, store: @evaluation_store,
      operated_by_user: @user, plan: previous, operated_at: Time.utc(2026, 9, 28, 12),
      operation_type: "listing_pricing", diff_result: { fields: { price: { from: 100, to: 120 } } })
    calls = []
    client = Object.new
    test_case = self
    client.define_singleton_method(:complete) do |request|
      if request.fetch(:tools).empty?
        calls << :evaluation
        { content: { effectiveness: "positive", confidence: "medium", summary: "Profit improved" } }
      else
        calls << :planner
        test_case.assert_equal "positive", previous.reload.latest_evaluation.effectiveness
        test_case.assert_includes request.fetch(:messages).last.fetch(:content), '"effectiveness":"positive"'
        { content: "No new plan needed", tool_calls: [] }
      end
    end
    metrics_query = Object.new
    metrics_query.define_singleton_method(:call) { { before: { after_tax_profit: 10 }, after: { after_tax_profit: 12 } } }
    arguments = { sku_code: @sku.sku_code, user: @user, client: client, as_of_date: Date.new(2026, 9, 29) }

    with_stubbed_singleton_method(Ec::SkuPlanningDataReadiness, :check!, ->(**) { calls << :readiness }) do
      with_stubbed_singleton_method(Ec::SkuOperationActionMetricsQuery, :new, ->(**) { metrics_query }) do
        conversation = ErpAI::SkuPlannerRunner.run(**arguments).sole
        assert_equal [previous.id], conversation.context.fetch("history_plan_ids")
        ErpAI::SkuPlannerRunner.run(**arguments)
      end
    end

    assert_equal [:readiness, :evaluation, :planner, :planner], calls
    assert_equal 1, previous.evaluations.count
    assert_equal "sku_plan_evaluation", previous.latest_evaluation.conversation.module_name
  end

  test "evaluation failure prevents creating a new planning revision" do
    previous = historical_plan
    failed = Struct.new(:status).new("failed")
    with_stubbed_singleton_method(Ec::SkuPlanningDataReadiness, :check!, ->(**) { true }) do
      with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :run, ->(**) { [failed] }) do
        assert_raises(ErpAI::SkuPlannerRunner::EvaluationFailed) do
          ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user, as_of_date: Date.new(2026, 9, 29),
            runner_factory: ->(**) { flunk "Planner must wait for evaluation" }).run
        end
      end
    end
    assert_empty @sku.planning_cycles
    assert previous.reload.is_latest?
  end

  test "planner waits for evaluation data readiness" do
    historical_plan
    with_stubbed_singleton_method(Ec::SkuPlanningDataReadiness, :check!, ->(**) { raise Ec::SkuPlanningDataReadiness::NotReady, "source incomplete" }) do
      with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :run, ->(**) { flunk "Evaluation must wait" }) do
        assert_raises(Ec::SkuPlanningDataReadiness::NotReady) do
          ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user, as_of_date: Date.new(2026, 9, 29),
            runner_factory: ->(**) { flunk "Planner must wait" }).run
        end
      end
    end
    assert_empty @sku.planning_cycles
  end

  test "planner skips evaluation while the historical execution window is still open" do
    previous = historical_plan
    previous.update!(execution_deadline: Date.new(2026, 9, 29))
    runner = Object.new
    runner.define_singleton_method(:ask) { |**| nil }
    with_stubbed_singleton_method(Ec::SkuPlanningDataReadiness, :check!, ->(**) { flunk "No evaluation is due" }) do
      with_stubbed_singleton_method(Ec::SkuOperationPlanEvaluationRunner, :run, ->(**) { flunk "Deadline is still open" }) do
        ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user, as_of_date: Date.new(2026, 9, 29),
          runner_factory: ->(**) { runner }).run
      end
    end
    assert_empty previous.evaluations
    assert_equal 1, @sku.planning_cycles.count
  end

  test "plan date uses Shanghai calendar day" do
    travel_to Time.utc(2026, 9, 21, 17, 30) do
      plan = @sku.sku_operation_plans.create!(target: "price", operation: "maintain",
        referer: [ "stock_risk" ], message: "After midnight")
      assert_equal Date.new(2026, 9, 22), plan.plan_date
    end
  end

  test "planner tool attaches its conversation to saved plans" do
    @user.roles << Role.find_by!(code: "manager")
    conversation = Agent.ensure_fixed!("sku_planner").conversations.create!(
      user: @user, module_name: "sku_planner", business_object_type: "Ec::Sku", business_object_id: @sku.id.to_s
    )
    executor = ErpAI::SkuPlannerRunner::ScopedToolExecutor.new(user: @user, sku: @sku)
    executor.conversation_id = conversation.id

    result = executor.call(id: "save", name: "save_sku_plan", arguments: {
      sku_code: @sku.sku_code, target: "price", operation: "maintain",
      referer: [ @diagnosis.events.first.id ], **plan_details
    })

    assert result.dig(:result, :success)
    plan = @sku.sku_operation_plans.find(result.dig(:result, :plan_id))
    assert_equal conversation.id, plan.conversation_id
    assert_equal [ @diagnosis.events.first.id ], plan.referer
    assert_equal plan.referer, result.dig(:result, :referer)
    assert_equal "SKU", plan.scope
    assert_equal @sku.sku_code, plan.scope_id
    assert_equal 1, plan.priority
    assert_equal "No price change", plan.constraints
    assert_equal "Keep price stable", result.dig(:result, :message)
  end

  test "planner executor preserves the requested planning date" do
    @user.roles << Role.find_by!(code: "manager")
    plan_date = Date.new(2026, 9, 28)
    @diagnosis.update!(created_at: Time.find_zone!("Asia/Shanghai").local(2026, 9, 28, 3))
    executor = ErpAI::SkuPlannerRunner::ScopedToolExecutor.new(user: @user, sku: @sku, plan_date: plan_date)

    result = executor.call(id: "backfill", name: "save_sku_plan", arguments: {
      sku_code: @sku.sku_code, target: "price", operation: "maintain",
      referer: [ @diagnosis.events.first.id ], **plan_details
    })

    plan = @sku.sku_operation_plans.find(result.dig(:result, :plan_id))
    assert_equal plan_date, plan.plan_date
    assert_equal plan_date.beginning_of_week(:monday), plan.planning_period_start
  end

  test "planner saves warehouse distribution and replenishment plans with decrease" do
    @user.roles << Role.find_by!(code: "manager")
    executor = ErpAI::SkuPlannerRunner::ScopedToolExecutor.new(user: @user, sku: @sku)
    schema = ErpAI::ToolRegistry.default_tools.find { |tool| tool[:name] == "save_sku_plan" }.fetch(:parameters)

    assert_includes schema.dig(:properties, :target, :enum), "warehouse_distribution"
    assert_includes schema.dig(:properties, :target, :enum), "replenishment"
    assert_includes schema.dig(:properties, :operation, :enum), "decrease"

    { "分仓" => "warehouse_distribution", "补货" => "replenishment" }.each do |target, expected_target|
      result = executor.call(id: target, name: "save_sku_plan", arguments: {
        sku_code: @sku.sku_code, target: target, operation: "降低",
        referer: [ @diagnosis.events.first.id ], **plan_details
      })

      assert result.dig(:result, :success)
      plan = @sku.sku_operation_plans.find(result.dig(:result, :plan_id))
      assert_equal expected_target, plan.target
      assert_equal "decrease", plan.operation
      assert_equal expected_target, result.dig(:result, :target)
      assert_equal "decrease", result.dig(:result, :operation)
    end
  end

  test "planner saves a listing-specific plan and rejects invalid scope or detail types" do
    @user.roles << Role.find_by!(code: "manager")
    store = Ec::Store.create!(platform: "wb", store_name: "Planner #{@token}", company_type: "small", is_active: true)
    listing = @sku.sku_products.create!(store: store, product_id: "PLANNER-#{@token}")
    executor = ErpAI::SkuPlannerRunner::ScopedToolExecutor.new(user: @user, sku: @sku)
    args = { sku_code: @sku.sku_code, target: "advertising", operation: "maintain",
             referer: [ @diagnosis.events.first.id ], **plan_details, scope: "LISTING", scope_id: listing.id.to_s }

    result = executor.call(id: "listing", name: "save_sku_plan", arguments: args)
    plan = @sku.sku_operation_plans.find(result.dig(:result, :plan_id))
    assert_equal listing.id.to_s, plan.scope_id
    assert_equal "LISTING", result.dig(:result, :scope)
    assert_equal "Expected savings", plan.expected_effect

    [ { scope_id: "unknown" }, { scope_id: "-1" }, { priority: "1" }, { constraints: [ "No price change" ] },
      { baseline: "" }, { message: 5 } ].each do |invalid|
      assert_raises(RuntimeError) { executor.call(id: "invalid", name: "save_sku_plan", arguments: args.merge(invalid)) }
    end
    assert_equal 1, @sku.sku_operation_plans.count
  ensure
    listing&.destroy!
    store&.destroy!
  end

  test "planner tool requires all detail fields with string types except priority" do
    schema = ErpAI::ToolRegistry.default_tools.find { |tool| tool[:name] == "save_sku_plan" }.fetch(:parameters)
    assert_equal %w[sku_code target operation referer scope scope_id priority message reason baseline constraints expected_effect], schema.fetch(:required)
    assert_equal "integer", schema.dig(:properties, :priority, :type)
    %i[scope scope_id message reason baseline constraints expected_effect].each do |field|
      assert_equal "string", schema.dig(:properties, field, :type)
    end
  end

  test "planner stores distinct event IDs and rejects unrelated references" do
    @user.roles << Role.find_by!(code: "manager")
    executor = ErpAI::SkuPlannerRunner::ScopedToolExecutor.new(user: @user, sku: @sku)
    first_event = @diagnosis.events.first
    same_type_event = @diagnosis.events.create!(sub_agent: create_rule, event_type: first_event.event_type, severity: "critical", message: "Same type, different event")
    info_event = @diagnosis.events.create!(sub_agent: create_rule, event_type: "routine_check", severity: "info", message: "No action needed")
    other_sku = Ec::Sku.create!(sku_code: "OTHER-PLANNER-#{@token}", product_name: "Other planner SKU")
    other_diagnosis = Ec::GeneralDiagnosis.create!(sku: other_sku, submitted_by: @user)
    other_event = other_diagnosis.events.create!(sub_agent: @rule, event_type: first_event.event_type, severity: "warning", message: "Other SKU event")
    args = { sku_code: @sku.sku_code, target: "price", operation: "maintain", **plan_details }

    [ [ first_event.event_type ], [ info_event.id ], [ other_event.id ], [ first_event.id, other_event.id ], [ 0 ] ].each do |referer|
      assert_raises(RuntimeError) do
        executor.call(id: "invalid", name: "save_sku_plan", arguments: args.merge(referer: referer))
      end
    end
    assert_empty @sku.sku_operation_plans

    result = executor.call(id: "save", name: "save_sku_plan",
      arguments: args.merge(referer: [ first_event.id, same_type_event.id, first_event.id ]))

    assert_equal [ first_event.id, same_type_event.id ], result.dig(:result, :referer)
    assert_equal [ first_event.id, same_type_event.id ], @sku.sku_operation_plans.find(result.dig(:result, :plan_id)).referer
  ensure
    other_diagnosis&.destroy!
    Ec::Sku.with_deleted.where(id: other_sku&.id).delete_all
  end

  test "planner rejects an event from a previous diagnosis" do
    @user.roles << Role.find_by!(code: "manager")
    stale_event = @diagnosis.events.first
    latest_diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user)
    latest_event = latest_diagnosis.events.create!(sub_agent: @rule, event_type: stale_event.event_type, severity: "warning", message: "Latest risk")
    executor = ErpAI::SkuPlannerRunner::ScopedToolExecutor.new(user: @user, sku: @sku)
    args = { sku_code: @sku.sku_code, target: "price", operation: "maintain", **plan_details }

    assert_raises(RuntimeError) do
      executor.call(id: "stale", name: "save_sku_plan", arguments: args.merge(referer: [ stale_event.id ]))
    end

    result = executor.call(id: "latest", name: "save_sku_plan", arguments: args.merge(referer: [ latest_event.id ]))
    assert_equal [ latest_event.id ], @sku.sku_operation_plans.find(result.dig(:result, :plan_id)).referer
  end

  private

  def create_rule(frequency: "daily")
    rule = Ec::SkuDiagnosisRule.create!(name: "Planner #{@token} #{@rules.size}", prompt: "Check the SKU", frequency: frequency)
    @rules << rule
    rule
  end

  def historical_plan
    create_plan("Previous week", plan_date: Date.new(2026, 9, 21), created_at: Time.utc(2026, 9, 21))
  end

  def with_stubbed_singleton_method(object, method_name, replacement)
    original = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end

  def plan_details
    { scope: "SKU", scope_id: @sku.sku_code, priority: 1, message: "Keep price stable",
      reason: "Low stock", baseline: "Current price unchanged", constraints: "No price change",
      expected_effect: "Expected savings" }
  end

  def create_plan(message, created_at: Time.current, plan_date: created_at.in_time_zone("Asia/Shanghai").to_date)
    @sku.sku_operation_plans.create!(target: "price", operation: "maintain", referer: [ "stock_risk" ],
                                     message: message, created_at: created_at, plan_date: plan_date)
  end

  def run_with_plan(message, fail_after_save: false)
    conversation = Agent.ensure_fixed!("sku_planner").conversations.create!(user: @user, module_name: "sku_planner")
    fake_runner = Object.new
    fake_runner.define_singleton_method(:ask) do |**_args|
      create_plan(message)
      raise "planner failed" if fail_after_save
      conversation
    end
    # The fake runner writes through the same table as the planner tool.
    fake_runner.define_singleton_method(:create_plan) { |value| @sku.sku_operation_plans.create!(target: "price", operation: "maintain", referer: [ "stock_risk" ], message: value) }
    fake_runner.instance_variable_set(:@sku, @sku)
    ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user,
      runner_factory: ->(**_args) { fake_runner }).run
  end
end
