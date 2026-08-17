require "test_helper"
require "ostruct"

class ErpAI::ActiveAgentClientTest < ActiveSupport::TestCase
  class FakeGeneration
    class << self
      attr_accessor :response, :responses, :generate_now_calls
    end

    attr_reader :params

    def initialize(params)
      @params = params
    end

    def analyze
      self
    end

    def generate_now
      self.class.generate_now_calls += 1
      return self.class.responses.shift if self.class.responses.present?

      self.class.response || OpenStruct.new(
        message: OpenStruct.new(content: "分析完成"),
        usage: { "total_tokens" => 18 }
      )
    end
  end

  class FakeAgent
    class << self
      attr_reader :last_generation

      def with(params)
        @last_generation = FakeGeneration.new(params)
      end
    end
  end

  setup do
    FakeGeneration.response = nil
    FakeGeneration.responses = nil
    FakeGeneration.generate_now_calls = 0
  end

  test "delegates completion request to active agent class" do
    result = ErpAI::ActiveAgentClient.new(agent_class: FakeAgent).complete(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "分析库存" }],
      tools: [{ name: "query_inventory_data" }],
      thinking_enabled: true
    )

    params = FakeAgent.last_generation.params

    assert_equal "custom-model", params.fetch(:model)
    assert_equal 0.2, params.fetch(:temperature)
    assert_equal "系统提示词", params.fetch(:system_prompt)
    assert_equal "ERP 上下文", params.fetch(:context)
    assert_equal [{ role: "user", content: "分析库存" }], params.fetch(:messages)
    assert_equal [{ name: "query_inventory_data" }], params.fetch(:available_tools)
    assert_not params.key?(:tools)
    assert_equal true, params.fetch(:thinking_enabled)
    assert_equal "分析完成", result.fetch(:content)
    assert_equal [], result.fetch(:tool_calls)
    assert_equal({ "total_tokens" => 18 }, result.fetch(:usage))
  end

  test "normalizes provider tool calls exposed on response message" do
    FakeGeneration.response = OpenStruct.new(
      message: OpenStruct.new(
        content: nil,
        tool_calls: [
          OpenStruct.new(
            id: "call_1",
            function: OpenStruct.new(
              name: "search__web_search",
              arguments: { "query" => "sku" }.to_json
            )
          )
        ]
      ),
      usage: { "total_tokens" => 20 }
    )

    result = ErpAI::ActiveAgentClient.new(agent_class: FakeAgent).complete(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "分析库存" }],
      tools: [],
      thinking_enabled: false
    )

    assert_nil result.fetch(:content)
    assert_equal [
      {
        id: "call_1",
        name: "search__web_search",
        arguments: { "query" => "sku" }
      }
    ], result.fetch(:tool_calls)
  end

  test "normalizes tool calls emitted as assistant JSON content" do
    FakeGeneration.response = OpenStruct.new(
      message: OpenStruct.new(
        content: {
          tool_calls: [
            {
              id: "call_1",
              name: "wiki__search",
              arguments: { query: "SKU" }
            }
          ]
        }.to_json
      ),
      usage: { "total_tokens" => 20 }
    )

    result = ErpAI::ActiveAgentClient.new(agent_class: FakeAgent).complete(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "查资料" }],
      tools: [{ name: "wiki__search", description: "Search wiki" }],
      thinking_enabled: false
    )

    assert_nil result.fetch(:content)
    assert_equal [
      {
        id: "call_1",
        name: "wiki__search",
        arguments: { "query" => "SKU" }
      }
    ], result.fetch(:tool_calls)
  end

  test "normalizes tool calls emitted in a markdown JSON block" do
    FakeGeneration.response = OpenStruct.new(
      message: OpenStruct.new(
        content: <<~CONTENT
          I will call the tool now.

          ```json
          {"tool_calls":[{"id":"call_1","name":"wiki__search","arguments":{"query":"SKU"}}]}
          ```
        CONTENT
      ),
      usage: { "total_tokens" => 20 }
    )

    result = ErpAI::ActiveAgentClient.new(agent_class: FakeAgent).complete(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "查资料" }],
      tools: [{ name: "wiki__search", description: "Search wiki" }],
      thinking_enabled: false
    )

    assert_nil result.fetch(:content)
    assert_equal "wiki__search", result.fetch(:tool_calls).first.fetch(:name)
  end

  test "extracts final content from a malformed content wrapper" do
    FakeGeneration.response = OpenStruct.new(
      message: OpenStruct.new(content: "{\"content\":\"## 分析摘要\n\n库存写入成功。        "),
      usage: { "total_tokens" => 20 },
      finish_reason: "stop"
    )

    result = ErpAI::ActiveAgentClient.new(agent_class: FakeAgent).complete(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "查资料" }],
      tools: [{ name: "wiki__search", description: "Search wiki" }],
      thinking_enabled: false
    )

    assert_equal "## 分析摘要\n\n库存写入成功。", result.fetch(:content)
    assert_equal [], result.fetch(:tool_calls)
    assert_equal 1, FakeGeneration.generate_now_calls
  end

  test "retries once when assistant tool call JSON is invalid" do
    FakeGeneration.responses = [
      OpenStruct.new(
        message: OpenStruct.new(content: "```json\n{\"tool_calls\":[{\"name\":\"wiki__search\"}]}}"),
        usage: { "total_tokens" => 10 }
      ),
      OpenStruct.new(
        message: OpenStruct.new(content: { tool_calls: [{ name: "wiki__search", arguments: { query: "SKU" } }] }.to_json),
        usage: { "total_tokens" => 20 }
      )
    ]

    result = ErpAI::ActiveAgentClient.new(agent_class: FakeAgent).complete(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "查资料" }],
      tools: [{ name: "wiki__search", description: "Search wiki" }],
      thinking_enabled: false
    )

    assert_equal 2, FakeGeneration.generate_now_calls
    assert_equal "wiki__search", result.fetch(:tool_calls).first.fetch(:name)
    retry_message = FakeAgent.last_generation.params.fetch(:messages).last.fetch(:content)
    assert_includes retry_message, '{"content":"非空的最终回答"}'
    assert_includes retry_message, "tool_calls 不得为空"
    assert_equal 2, FakeAgent.last_generation.params.fetch(:messages).size
  end

  test "retries once when assistant returns an empty tool call list" do
    FakeGeneration.responses = [
      OpenStruct.new(
        message: OpenStruct.new(content: { tool_calls: [] }.to_json),
        usage: { "total_tokens" => 10 }
      ),
      OpenStruct.new(
        message: OpenStruct.new(content: { content: "分析完成" }.to_json),
        usage: { "total_tokens" => 20 }
      )
    ]

    result = ErpAI::ActiveAgentClient.new(agent_class: FakeAgent).complete(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "查资料" }],
      tools: [{ name: "wiki__search", description: "Search wiki" }],
      thinking_enabled: false
    )

    assert_equal 2, FakeGeneration.generate_now_calls
    assert_equal "分析完成", result.fetch(:content)
  end

  test "retries once when assistant response is empty" do
    FakeGeneration.responses = [
      OpenStruct.new(
        message: OpenStruct.new(content: nil, tool_calls: []),
        usage: { "total_tokens" => 10 }
      ),
      OpenStruct.new(
        message: OpenStruct.new(content: { content: "分析完成" }.to_json),
        usage: { "total_tokens" => 20 }
      )
    ]

    result = ErpAI::ActiveAgentClient.new(agent_class: FakeAgent).complete(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "查资料" }],
      tools: [{ name: "wiki__search", description: "Search wiki" }],
      thinking_enabled: false
    )

    assert_equal 2, FakeGeneration.generate_now_calls
    assert_equal "分析完成", result.fetch(:content)
  end

  test "raises after retrying invalid assistant tool call JSON" do
    invalid_response = OpenStruct.new(
      message: OpenStruct.new(content: "{\"tool_calls\":[{\"name\":\"wiki__search\"}]}}"),
      usage: { "total_tokens" => 10, "output_tokens" => 1_384 }
    )
    FakeGeneration.responses = [invalid_response, invalid_response]

    error = assert_raises ErpAI::ActiveAgentClient::InvalidResponse do
      ErpAI::ActiveAgentClient.new(agent_class: FakeAgent).complete(
        model: "custom-model",
        temperature: 0.2,
        system_prompt: "系统提示词",
        context: "ERP 上下文",
        messages: [{ role: "user", content: "查资料" }],
        tools: [{ name: "wiki__search", description: "Search wiki" }],
        thinking_enabled: false
      )
    end

    assert_equal 2, FakeGeneration.generate_now_calls
    assert_includes error.message, "output_tokens=1384"
    assert_includes error.message, "content_bytes=41"
    assert_includes error.message, "json_error="
    assert_includes error.message, "content_head="
    assert_includes error.message, "content_tail="
  end

  test "extracts final content from assistant JSON content" do
    FakeGeneration.response = OpenStruct.new(
      message: OpenStruct.new(content: { content: "最终回答" }.to_json),
      usage: { "total_tokens" => 20 }
    )

    result = ErpAI::ActiveAgentClient.new(agent_class: FakeAgent).complete(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "总结" }],
      tools: [{ name: "wiki__search", description: "Search wiki" }],
      thinking_enabled: false
    )

    assert_equal "最终回答", result.fetch(:content)
    assert_equal [], result.fetch(:tool_calls)
  end

  test "default client delegates to active agent client" do
    old_default_client = ErpAI::DefaultClient.default_client
    ErpAI::DefaultClient.default_client = ErpAI::ActiveAgentClient.new(agent_class: FakeAgent)

    result = ErpAI::DefaultClient.new.complete(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "翻译库存" }],
      tools: [],
      thinking_enabled: false
    )

    params = FakeAgent.last_generation.params
    assert_equal "custom-model", params.fetch(:model)
    assert_equal "翻译库存", params.fetch(:messages).first.fetch(:content)
    assert_equal false, params.fetch(:thinking_enabled)
    assert_equal "分析完成", result.fetch(:content)
  ensure
    ErpAI::DefaultClient.default_client = old_default_client
  end
end
