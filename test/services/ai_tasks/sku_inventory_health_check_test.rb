require "test_helper"

class AITasks::SkuInventoryHealthCheckTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4)
    @user = User.create!(
      email: "ai-task-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @agent = Agent.find_by(code: "sku-inventory-health-check-web")
    @created_agent = @agent.nil?
    @agent ||= Agent.create!(
      code: "sku-inventory-health-check-web",
      name: "Inventory health check",
      system_prompt: "Analyze inventory health.",
      model_id: "fake-model",
      temperature: 0.3,
      tools: []
    )
  end

  teardown do
    Agent.where(id: @agent&.id).delete_all if @created_agent
    User.where(id: @user&.id).delete_all
  end

  test "asks the inventory health agent to analyze the previous natural week" do
    conversation = Object.new
    expected_question = "分析SKU-1 并写入events，上个自然周日期范围：2026-07-20~2026-07-26"
    assert_question = ->(question) { assert_equal expected_question, question }
    runner = Object.new
    runner.define_singleton_method(:ask) do |question:|
      assert_question.call(question)
      conversation
    end

    assert_runner_args = lambda do |agent:, user:|
      assert_equal @agent, agent
      assert_equal User.take, user
    end
    original_new = ErpAI::AgentRunner.method(:new)
    ErpAI::AgentRunner.define_singleton_method(:new) do |agent:, user:|
      assert_runner_args.call(agent:, user:)
      runner
    end

    travel_to Time.zone.local(2026, 7, 27, 12) do
      result = AITasks::SkuInventoryHealthCheck.run(sku_code: "SKU-1")

      assert_same conversation, result
    end
  ensure
    if original_new
      ErpAI::AgentRunner.define_singleton_method(:new, original_new)
    end
  end
end
