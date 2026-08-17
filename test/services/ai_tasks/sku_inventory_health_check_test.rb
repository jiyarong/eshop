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
    @sku = Ec::Sku.create!(
      sku_code: "INVENTORY-HEALTH-#{@token.upcase}",
      product_name: "Inventory health check",
      is_active: true
    )
  end

  teardown do
    Ec::RestockingDiagnosis.where(sku_id: @sku&.id).destroy_all
    @conversation&.destroy!
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    Agent.where(id: @agent&.id).delete_all if @created_agent
    User.where(id: @user&.id).delete_all
  end

  test "asks the inventory health agent to analyze the previous natural week and links its result" do
    existing_diagnosis = Ec::RestockingDiagnosis.create!(sku: @sku, submitted_by: @user, analyzed_at: 1.day.ago)
    existing_event = existing_diagnosis.events.create!(
      event_type: "existing",
      severity: "info",
      message: "Existing result",
      position: 0
    )
    expected_question = "分析#{@sku.sku_code} 并写入events，上个自然周日期范围：2026-07-20~2026-07-26"
    assert_question = ->(question) { assert_equal expected_question, question }
    assert_data_summary = ->(data_summary) { assert data_summary.present? }
    remember_conversation = ->(conversation) { @conversation = conversation }
    agent = @agent
    sku = @sku
    selected_user = nil
    new_event = nil
    runner = Object.new
    runner.define_singleton_method(:ask) do |question:, data_summary:|
      assert_question.call(question)
      assert_data_summary.call(data_summary)
      conversation = agent.conversations.create!(user: selected_user)
      remember_conversation.call(conversation)
      conversation.messages.create!(role: "user", content: question)
      conversation.messages.create!(role: "assistant", content: "Inventory health result")
      diagnosis = Ec::RestockingDiagnosis.create!(sku: sku, submitted_by: selected_user, analyzed_at: Time.current)
      new_event = diagnosis.events.create!(
        event_type: "inventory_sufficient",
        severity: "green",
        message: "Inventory is sufficient",
        position: 0
      )
      conversation
    end

    assert_runner_args = lambda do |agent:, user:|
      assert_equal @agent, agent
      assert_equal User.take, user
      selected_user = user
    end
    original_new = ErpAI::AgentRunner.method(:new)
    ErpAI::AgentRunner.define_singleton_method(:new) do |agent:, user:|
      assert_runner_args.call(agent:, user:)
      runner
    end

    travel_to Time.zone.local(2026, 7, 27, 12) do
      @conversation = AITasks::SkuInventoryHealthCheck.run(sku_code: @sku.sku_code)

      assert_equal @conversation, new_event.reload.conversation
      assert_equal [ "user", "assistant" ], @conversation.messages.order(:created_at, :id).pluck(:role)
      assert_nil existing_event.reload.conversation_id
    end
  ensure
    if original_new
      ErpAI::AgentRunner.define_singleton_method(:new, original_new)
    end
  end
end
