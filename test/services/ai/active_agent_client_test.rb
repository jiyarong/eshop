require "test_helper"
require "ostruct"

class ErpAI::ActiveAgentClientTest < ActiveSupport::TestCase
  class FakeGeneration
    attr_reader :params

    def initialize(params)
      @params = params
    end

    def analyze
      self
    end

    def generate_now
      OpenStruct.new(
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

  test "delegates completion request to active agent class" do
    result = ErpAI::ActiveAgentClient.new(agent_class: FakeAgent).complete(
      model: "custom-model",
      temperature: 0.2,
      system_prompt: "系统提示词",
      context: "ERP 上下文",
      messages: [{ role: "user", content: "分析库存" }],
      tools: [{ name: "query_inventory_data" }]
    )

    params = FakeAgent.last_generation.params

    assert_equal "custom-model", params.fetch(:model)
    assert_equal 0.2, params.fetch(:temperature)
    assert_equal "系统提示词", params.fetch(:system_prompt)
    assert_equal "ERP 上下文", params.fetch(:context)
    assert_equal [{ role: "user", content: "分析库存" }], params.fetch(:messages)
    assert_equal [{ name: "query_inventory_data" }], params.fetch(:tools)
    assert_equal "分析完成", result.fetch(:content)
    assert_equal({ "total_tokens" => 18 }, result.fetch(:usage))
  end
end
