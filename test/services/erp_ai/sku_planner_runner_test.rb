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
      referer: [ "stock_risk" ], message: "Keep price stable"
    })

    assert result.dig(:result, :success)
    assert_equal conversation.id, @sku.sku_operation_plans.find(result.dig(:result, :plan_id)).conversation_id
  end

  private

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
