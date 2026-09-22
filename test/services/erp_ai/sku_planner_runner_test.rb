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
    previous = create_plan("Previous", created_at: 1.day.ago)
    replaced = create_plan("Replaced")

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

  private

  def create_plan(message, created_at: Time.current)
    @sku.sku_operation_plans.create!(target: "price", operation: "maintain", referer: [ "stock_risk" ],
                                     message: message, created_at: created_at)
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
