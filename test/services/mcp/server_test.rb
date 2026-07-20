require "test_helper"

class Mcp::ServerTest < ActiveSupport::TestCase
  class FakeExternalClient
    attr_reader :called_tool_name, :called_arguments

    def list_tools
      raise "gbrain definitions must not depend on upstream tools/list"
    end

    def call_tool(tool_name, arguments)
      @called_tool_name = tool_name
      @called_arguments = arguments
      {
        "content" => [ { "type" => "text", "text" => "external result" } ],
        "structuredContent" => { "source" => "gbrain" }
      }
    end
  end

  class FakeExternalServerRegistry
    attr_reader :client

    def initialize
      @client = FakeExternalClient.new
    end

    def clients
      { "gbrain" => client }
    end

    def tool_filters
      {
        "gbrain" => %w[query search get_page list_pages traverse_graph think]
      }
    end
  end

  class EmptyExternalServerRegistry
    def clients
      {}
    end

    def tool_filters
      {}
    end
  end

  setup do
    @external_server_registry = FakeExternalServerRegistry.new
    @server = Mcp::Server.new(
      current_user: Object.new,
      external_server_registry: @external_server_registry
    )
  end

  test "lists ecommerce knowledge tools with constrained schemas" do
    response = @server.call(rpc_request("tools/list"))
    tools = response.fetch(:result).fetch(:tools)
    tool_names = tools.map { |tool| tool[:name] || tool["name"] }

    assert_includes tool_names, "sql_query"
    assert_equal %w[
      gbrain__get_page
      gbrain__list_pages
      gbrain__query
      gbrain__search
      gbrain__think
      gbrain__traverse_graph
    ], tool_names.grep(/\Agbrain__/).sort
    assert_not_includes tool_names, "gbrain__delete_page"

    external_tool = tools.find { |tool| (tool[:name] || tool["name"]) == "gbrain__query" }
    schema = external_tool.fetch("inputSchema")
    assert_equal false, schema.fetch("additionalProperties")
    assert_equal [ "query" ], schema.fetch("required")
    assert_equal %w[low medium high], schema.dig("properties", "detail", :enum)
    assert_equal 50, schema.dig("properties", "limit", :maximum)
    assert_not schema.fetch("properties").key?("image")
    assert_not schema.fetch("properties").key?("model")

    think_schema = tools.find { |tool| tool["name"] == "gbrain__think" }.fetch("inputSchema")
    assert_equal %w[anchor question rounds since until], think_schema.fetch("properties").keys.sort
    assert_equal 3, think_schema.dig("properties", "rounds", :maximum)

    graph_schema = tools.find { |tool| tool["name"] == "gbrain__traverse_graph" }.fetch("inputSchema")
    assert_equal 3, graph_schema.dig("properties", "depth", :maximum)
  end

  test "does not advertise gbrain tools when the server is not configured" do
    server = Mcp::Server.new(
      current_user: Object.new,
      external_server_registry: EmptyExternalServerRegistry.new
    )

    tools = server.call(rpc_request("tools/list")).fetch(:result).fetch(:tools)
    tool_names = tools.map { |tool| tool[:name] || tool["name"] }

    assert_empty tool_names.grep(/\Agbrain__/)
  end

  test "routes precise search through query with cheap hybrid defaults" do
    travel_to Time.zone.local(2026, 7, 20, 12) do
      response = @server.call(rpc_request(
        "tools/call",
        {
          "name" => "gbrain__search",
          "arguments" => {
            "query" => "Ozon RU 西伯利亚 FBO 仓储布局",
            "source_id" => "ozon-ru",
            "recency" => "strong",
            "since" => "90d",
            "unknown" => "discarded"
          }
        }
      ))

      result = response.fetch(:result)
      assert_equal "query", @external_server_registry.client.called_tool_name
      assert_equal({
        "limit" => 10,
        "detail" => "medium",
        "adaptive_return" => true,
        "recency" => "strong",
        "query" => "Ozon RU 西伯利亚 FBO 仓储布局",
        "source_id" => "ozon-ru",
        "since" => "2026-04-21",
        "expand" => false
      }, @external_server_registry.client.called_arguments)
      assert_equal "external result", result.fetch("content").first.fetch("text")
      assert_equal "gbrain", result.dig("structuredContent", "source")
    end
  end

  test "preserves explicit policy and broad research query controls" do
    travel_to Time.zone.local(2026, 7, 20, 12) do
      @server.call(rpc_request(
        "tools/call",
        {
          "name" => "gbrain__query",
          "arguments" => {
            "query" => "Ozon RU 最新物流费用政策",
            "source_id" => "ozon-ru",
            "expand" => false,
            "recency" => "strong",
            "since" => "90d",
            "autocut" => false,
            "limit" => 30,
            "image" => "discarded"
          }
        }
      ))

      assert_equal "query", @external_server_registry.client.called_tool_name
      assert_equal({
        "limit" => 30,
        "detail" => "medium",
        "expand" => false,
        "query" => "Ozon RU 最新物流费用政策",
        "source_id" => "ozon-ru",
        "recency" => "strong",
        "since" => "2026-04-21",
        "autocut" => false
      }, @external_server_registry.client.called_arguments)
    end
  end

  test "keeps think calls non-persistent" do
    @server.call(rpc_request(
      "tools/call",
      {
        "name" => "gbrain__think",
        "arguments" => {
          "question" => "Ozon RU 西伯利亚 FBO 应该如何布局",
          "anchor" => "regions/ozon-ru-siberia",
          "save" => true,
          "take" => true,
          "model" => "custom-model"
        }
      }
    ))

    assert_equal "think", @external_server_registry.client.called_tool_name
    assert_equal({
      "rounds" => 1,
      "question" => "Ozon RU 西伯利亚 FBO 应该如何布局",
      "anchor" => "regions/ozon-ru-siberia"
    }, @external_server_registry.client.called_arguments)
  end

  test "publishes ecommerce retrieval instructions during initialization" do
    response = @server.call(rpc_request("initialize"))
    instructions = response.fetch(:result).fetch(:instructions)

    assert_includes instructions, "平台、国家、地区、品类层级、主题和时效要求"
    assert_includes instructions, "最相关的 3-5 个完整页面"
    assert_includes instructions, "复核日期"
    assert_includes instructions, "category-l1/"
  end

  test "rejects external MCP tool calls outside the allowlist" do
    response = @server.call(rpc_request(
      "tools/call",
      {
        "name" => "gbrain__delete_page",
        "arguments" => {}
      }
    ))

    result = response.fetch(:result)
    error = JSON.parse(result.fetch(:content).first.fetch(:text))
    assert_equal true, result.fetch(:isError)
    assert_equal "mcp_tool_not_allowed", error.fetch("code")
    assert_nil @external_server_registry.client.called_tool_name
  end

  private

  def rpc_request(method, params = {})
    {
      "jsonrpc" => "2.0",
      "id" => "test-id",
      "method" => method,
      "params" => params
    }
  end
end
