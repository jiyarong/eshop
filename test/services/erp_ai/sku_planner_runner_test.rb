require "test_helper"

class ErpAI::SkuPlannerRunnerTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "PLANNER-#{@token}", product_name: "Planner test")
    @user = User.create!(email: "planner-#{@token.downcase}@example.com", password: "password123")
    @agent_existed = Agent.exists?(code: "sku_planner")
    @diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user)
    @diagnosis.events.create!(event_type: "stock_risk", severity: "warning", message: "Stock is low")
  end

  teardown do
    @sku.sku_operation_plans.delete_all
    @sku.ai_diagnoses.destroy_all
    Message.where(conversation: Conversation.where(user: @user)).delete_all
    Conversation.where(user: @user).delete_all
    Agent.where(code: "sku_planner").delete_all unless @agent_existed
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    UserRole.where(user_id: @user.id).delete_all
    User.where(id: @user.id).delete_all
  end

  test "same-day rerun replaces plans and makes previous days non-latest" do
    today = Time.current.in_time_zone("Asia/Shanghai").to_date
    previous = create_plan("Previous", plan_date: today - 1.day)
    replaced = create_plan("Replaced", created_at: 1.day.ago, plan_date: today)

    run_with_plan("First")
    assert_not Ec::SkuOperationPlan.exists?(replaced.id)
    assert_equal [ "First" ], @sku.sku_operation_plans.latest.pluck(:message)
    assert_not previous.reload.is_latest?

    run_with_plan("Second")
    assert_equal [ "Second" ], @sku.sku_operation_plans.latest.pluck(:message)
    assert_equal 2, @sku.sku_operation_plans.count
  end

  test "failed run restores deleted plans and discards partially generated plans" do
    previous = create_plan("Previous", created_at: 1.day.ago)
    existing = create_plan("Existing")

    run_with_plan("Partial", fail_after_save: true)

    assert_equal [ "Previous", "Existing" ], @sku.sku_operation_plans.order(:created_at).pluck(:message)
    assert previous.reload.is_latest?
    assert existing.reload.is_latest?
  end

  test "planner context excludes info events and explains all three severity levels" do
    @diagnosis.events.create!(event_type: "routine_check", severity: "info", message: "No action needed")
    @diagnosis.events.create!(event_type: "urgent_stock", severity: "critical", message: "Immediate action")
    captured = nil
    fake_runner = Object.new
    fake_runner.define_singleton_method(:ask) { |**args| captured = args }

    ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user,
      runner_factory: ->(**_args) { fake_runner }).run

    events = JSON.parse(captured.fetch(:data_summary))
    assert_equal %w[stock_risk urgent_stock], events.map { |event| event.fetch("event_type") }
    assert_equal @diagnosis.events.where.not(severity: "info").order(:position, :id).pluck(:id), events.map { |event| event.fetch("id") }
    assert_includes captured.fetch(:question), "事件 id"
    assert_includes captured.fetch(:question), "info 是仅供了解"
    assert_includes captured.fetch(:question), "warning 是需要关注"
    assert_includes captured.fetch(:question), "critical 是需要优先处理"
  end

  test "planner skips SKUs with only info events" do
    @diagnosis.events.delete_all
    @diagnosis.events.create!(event_type: "routine_check", severity: "info", message: "No action needed")
    existing = create_plan("Existing")

    result = ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user,
      runner_factory: ->(**_args) { flunk "Planner should not run for info-only events" }).run

    assert_empty result
    assert existing.reload.is_latest?
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
    same_type_event = @diagnosis.events.create!(event_type: first_event.event_type, severity: "critical", message: "Same type, different event")
    info_event = @diagnosis.events.create!(event_type: "routine_check", severity: "info", message: "No action needed")
    other_sku = Ec::Sku.create!(sku_code: "OTHER-PLANNER-#{@token}", product_name: "Other planner SKU")
    other_diagnosis = Ec::GeneralDiagnosis.create!(sku: other_sku, submitted_by: @user)
    other_event = other_diagnosis.events.create!(event_type: first_event.event_type, severity: "warning", message: "Other SKU event")
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
    latest_event = latest_diagnosis.events.create!(event_type: stale_event.event_type, severity: "warning", message: "Latest risk")
    executor = ErpAI::SkuPlannerRunner::ScopedToolExecutor.new(user: @user, sku: @sku)
    args = { sku_code: @sku.sku_code, target: "price", operation: "maintain", **plan_details }

    assert_raises(RuntimeError) do
      executor.call(id: "stale", name: "save_sku_plan", arguments: args.merge(referer: [ stale_event.id ]))
    end

    result = executor.call(id: "latest", name: "save_sku_plan", arguments: args.merge(referer: [ latest_event.id ]))
    assert_equal [ latest_event.id ], @sku.sku_operation_plans.find(result.dig(:result, :plan_id)).referer
  end

  private

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
    fake_runner = Object.new
    fake_runner.define_singleton_method(:ask) do |**_args|
      create_plan(message)
      raise "planner failed" if fail_after_save
    end
    # The fake runner writes through the same table as the planner tool.
    fake_runner.define_singleton_method(:create_plan) { |value| @sku.sku_operation_plans.create!(target: "price", operation: "maintain", referer: [ "stock_risk" ], message: value) }
    fake_runner.instance_variable_set(:@sku, @sku)
    ErpAI::SkuPlannerRunner.new(sku_code: @sku.sku_code, user: @user,
      runner_factory: ->(**_args) { fake_runner }).run
  end
end
