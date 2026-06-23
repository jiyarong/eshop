require "test_helper"

class BusinessAnalysisAgentTest < ActiveSupport::TestCase
  test "passes each message separately to active agent prompt" do
    generation = BusinessAnalysisAgent.with(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [
        { role: "user", content: "分析库存" },
        { role: "assistant", content: "已有结论" }
      ],
      tools: [],
      thinking_enabled: false
    ).analyze

    assert_equal [
      { role: "system", content: "系统提示词\n\nERP 上下文" },
      { role: "user", content: "分析库存" },
      { role: "assistant", content: "已有结论" }
    ], generation.messages
    assert generation.messages.none? { |message| message.is_a?(Array) }
  end

  test "uses system role instead of developer role for provider compatibility" do
    generation = BusinessAnalysisAgent.with(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "分析库存" }],
      tools: [],
      thinking_enabled: false
    ).analyze

    assert_equal ["system", "user"], generation.messages.map { |message| message.fetch(:role) }
    assert_equal "系统提示词\n\nERP 上下文", generation.messages.first.fetch(:content)
  end

  test "adds thinking option only when enabled" do
    enabled_generation = BusinessAnalysisAgent.with(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "分析库存" }],
      tools: [],
      thinking_enabled: true
    ).analyze

    disabled_generation = BusinessAnalysisAgent.with(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "分析库存" }],
      tools: [],
      thinking_enabled: false
    ).analyze

    assert_equal "medium", enabled_generation.options.fetch(:reasoning_effort)
    assert_not disabled_generation.options.key?(:reasoning_effort)
  end
end
