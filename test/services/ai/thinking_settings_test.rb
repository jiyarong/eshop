require "test_helper"

class ErpAI::ThinkingSettingsTest < ActiveSupport::TestCase
  test "offers only the levels supported by each model family" do
    {
      "deepseek-v4-flash" => %w[low high max],
      "deepseek-v4-pro" => %w[low high max],
      "deepseek-flash" => %w[low high max],
      "deepseek-chat" => [],
      "gpt-5" => %w[minimal low medium high],
      "gpt-5-mini" => %w[minimal low medium high],
      "gpt-5-nano-2025-08-07" => %w[minimal low medium high],
      "gpt-5.1" => %w[low medium high],
      "gpt-5.1-2025-11-13" => %w[low medium high],
      "gpt-5.2" => %w[low medium high xhigh],
      "gpt-5.4-mini" => %w[low medium high xhigh],
      "gpt-5.6-sol" => %w[low medium high xhigh max],
      "gpt-6-astra" => %w[low medium high xhigh max],
      "gpt-6-sol" => %w[low medium high xhigh max],
      "gpt-6.1-sol" => %w[low medium high xhigh max],
      "gpt-4.1-mini" => [],
      "gpt-5-chat-latest" => [],
      "gpt-5.2-pro" => [],
      "gpt-5.1-codex" => [],
      "custom-model" => []
    }.each do |model, levels|
      assert_equal levels, ErpAI::ThinkingSettings.levels_for(model), model
    end
  end

  test "validates saved thinking levels against the selected model" do
    agent = Agent.new(code: "thinking_test", name: "Thinking", system_prompt: "Test", model_id: "deepseek-v4-flash")
    agent.thinking_level = "max"
    assert agent.valid?

    agent.thinking_level = "medium"
    assert_not agent.valid?
    assert agent.errors.added?(:thinking_level, :inclusion, value: "medium")

    agent.model_id = "gpt-5.2"
    agent.thinking_level = "xhigh"
    assert agent.valid?

    agent.model_id = "gpt-4.1"
    assert_not agent.valid?
    agent.thinking_level = ""
    assert agent.valid?
  end

  test "uses the configured enabled level and model-specific disabled level" do
    assert_equal "xhigh", effort("gpt-5.2", enabled: true, level: "xhigh")
    assert_equal "medium", effort("gpt-5.2", enabled: true, level: "")
    assert_equal "none", effort("gpt-5.2", enabled: false, level: "xhigh")
    assert_equal "minimal", effort("gpt-5", enabled: false, level: "high")
    assert_equal "low", effort("gpt-6-astra", enabled: false, level: "max")
    assert_equal "low", effort("gpt-6.1-sol", enabled: false, level: "max")
    assert_equal "none", effort("gpt-6-sol", enabled: false, level: "max")
    assert_equal "max", effort("deepseek-v4-flash", enabled: true, level: "max")
    assert_nil effort("deepseek-v4-flash", enabled: false, level: "max")
    assert_nil effort("deepseek-v4-flash", enabled: true, level: "")
    assert_raises(ArgumentError) { effort("deepseek-v4-flash", enabled: true, level: "medium") }
  end

  private

  def effort(model, enabled:, level:)
    ErpAI::ThinkingSettings.reasoning_effort(model: model, enabled: enabled, level: level)
  end
end
