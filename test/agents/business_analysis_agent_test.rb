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
      messages: [ { role: "user", content: "分析库存" } ],
      tools: [],
      thinking_enabled: false
    ).analyze

    assert_equal ["system", "user"], generation.messages.map { |message| message.fetch(:role) }
    assert_equal "系统提示词\n\nERP 上下文", generation.messages.first.fetch(:content)
  end

  test "sets DeepSeek thinking request option from agent configuration" do
    enabled_generation = BusinessAnalysisAgent.with(
      model: "deepseek-chat",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "分析库存" }],
      tools: [],
      thinking_enabled: true
    ).analyze

    disabled_generation = BusinessAnalysisAgent.with(
      model: "deepseek-chat",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "分析库存" }],
      tools: [],
      thinking_enabled: false
    ).analyze

    assert_equal({ thinking: { type: "enabled" } }, enabled_generation.options.dig(:request_options, :extra_body))
    assert_equal({ thinking: { type: "disabled" } }, disabled_generation.options.dig(:request_options, :extra_body))
    assert_not enabled_generation.options.key?(:reasoning_effort)
  end

  test "does not send DeepSeek thinking option to non DeepSeek models" do
    generation = BusinessAnalysisAgent.with(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "分析库存" }],
      tools: [],
      thinking_enabled: false
    ).analyze

    assert_not generation.options.key?(:request_options)
  end

  test "sends configured DeepSeek effort only when thinking is enabled" do
    %w[low high max].each do |level|
      generation = thinking_generation(model: "deepseek-v4-flash", enabled: true, level: level)
      assert_equal({ thinking: { type: "enabled" }, reasoning_effort: level }, generation.options.dig(:request_options, :extra_body))
    end

    generation = thinking_generation(model: "deepseek-v4-flash", enabled: false, level: "max")
    assert_equal({ thinking: { type: "disabled" } }, generation.options.dig(:request_options, :extra_body))
  end

  test "sends configured GPT effort without incompatible sampling or token parameters" do
    { "gpt-5" => "minimal", "gpt-5.1" => "high", "gpt-5.2" => "xhigh", "gpt-6-astra" => "max" }.each do |model, level|
      generation = thinking_generation(model: model, enabled: true, level: level)
      assert_equal({ reasoning_effort: level }, generation.options.dig(:request_options, :extra_body))
      assert_equal 65_536, generation.options.fetch(:max_completion_tokens)
      assert_not generation.options.key?(:max_tokens)
      assert_not generation.options.key?(:temperature)
      serialized = ActiveAgent::Providers::OpenAI::Chat::Request.new(**generation.options.except(:request_options), messages: generation.messages).serialize
      assert_not serialized.key?(:temperature)
      assert_not serialized.key?(:top_p)
      assert_not serialized.key?(:max_tokens)
    end
  end

  test "disables GPT reasoning using its supported minimum and keeps temperature only for none" do
    { "gpt-5" => "minimal", "gpt-5.2" => "none", "gpt-6-astra" => "low" }.each do |model, effort|
      generation = thinking_generation(model: model, enabled: false, level: "high")
      assert_equal effort, generation.options.dig(:request_options, :extra_body, :reasoning_effort)
      assert_equal effort == "none", generation.options.key?(:temperature)
    end
  end

  test "preserves thinking settings in the SDK HTTP request body including max effort" do
    sdk_client = OpenAI::Client.new(api_key: "test-token")
    provider = ActiveAgent::Providers::OpenAI::ChatProvider.new(service: "OpenAI", access_token: "test-token")

    %w[deepseek-v4-flash gpt-6-astra].each do |model|
      generation = thinking_generation(model: model, enabled: true, level: "max")
      request = ActiveAgent::Providers::OpenAI::Chat::Request.new(**generation.options, messages: generation.messages)
      parameters = provider.send(:api_request_build, request, provider.class.prompt_request_type)
      body, request_options = OpenAI::Models::Chat::CompletionCreateParams.dump_request(parameters)
      http_request = sdk_client.send(:build_request, { method: :post, path: "chat/completions", body: body }, request_options)
      payload = JSON.parse(http_request.fetch(:body))

      assert_equal model, payload.fetch("model")
      assert_equal "max", payload.fetch("reasoning_effort")
      assert_not payload.key?("request_options")
      if model.start_with?("deepseek")
        assert_equal({ "type" => "enabled" }, payload.fetch("thinking"))
      else
        assert_not payload.key?("thinking")
        assert_not payload.key?("temperature")
      end
    end
  end

  test "enables provider streaming when a callback is provided" do
    generation = BusinessAnalysisAgent.with(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "分析库存" }],
      available_tools: [],
      thinking_enabled: false,
      stream_callback: proc { |_delta| }
    ).analyze

    assert_equal true, generation.options.fetch(:stream)
  end

  test "describes available tools in system prompt without native tool options" do
    generation = BusinessAnalysisAgent.with(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "分析库存" }],
      available_tools: [{ name: "search__web_search", description: "Search" }],
      thinking_enabled: false
    ).analyze

    assert_not generation.options.key?(:tools)
    assert_equal({ type: "json_object" }, generation.options.fetch(:response_format))
    assert_equal 65_536, generation.options.fetch(:max_tokens)
    assert_includes generation.messages.first.fetch(:content), "search__web_search"
    assert_includes generation.messages.first.fetch(:content), "tool_calls"
    assert_match(/\bjson\b/, generation.messages.first.fetch(:content))
  end

  private

  def thinking_generation(model:, enabled:, level:)
    BusinessAnalysisAgent.with(
      model: model,
      temperature: 0.2,
      system_prompt: "Test",
      context: "",
      messages: [ { role: "user", content: "Test" } ],
      available_tools: [ { name: "query_inventory_data" } ],
      thinking_enabled: enabled,
      thinking_level: level
    ).analyze
  end
end
