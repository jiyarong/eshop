require "test_helper"

class Mcp::ServerTest < ActiveSupport::TestCase
  class FakeExternalClient
    attr_reader :called_tool_name, :called_arguments

    def list_tools
      [
        {
          "name" => "query",
          "description" => "Query external knowledge",
          "inputSchema" => {
            "type" => "object",
            "properties" => { "question" => { "type" => "string" } }
          }
        },
        {
          "name" => "delete_page",
          "description" => "Delete a page",
          "inputSchema" => { "type" => "object" }
        }
      ]
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
      { "gbrain" => [ "query" ] }
    end
  end

  setup do
    @external_server_registry = FakeExternalServerRegistry.new
    @server = Mcp::Server.new(
      current_user: Object.new,
      external_server_registry: @external_server_registry
    )
  end

  test "lists local tools and only enabled external MCP tools" do
    response = @server.call(rpc_request("tools/list"))
    tools = response.fetch(:result).fetch(:tools)
    tool_names = tools.map { |tool| tool[:name] || tool["name"] }

    assert_includes tool_names, "sql_query"
    assert_includes tool_names, "gbrain__query"
    assert_not_includes tool_names, "gbrain__delete_page"

    external_tool = tools.find { |tool| tool["name"] == "gbrain__query" }
    assert_equal "string", external_tool.dig("inputSchema", "properties", "question", "type")
  end

  test "proxies enabled external MCP tool calls and preserves the upstream result" do
    response = @server.call(rpc_request(
      "tools/call",
      {
        "name" => "gbrain__query",
        "arguments" => { "question" => "inventory" }
      }
    ))

    result = response.fetch(:result)
    assert_equal "query", @external_server_registry.client.called_tool_name
    assert_equal({ "question" => "inventory" }, @external_server_registry.client.called_arguments)
    assert_equal "external result", result.fetch("content").first.fetch("text")
    assert_equal "gbrain", result.dig("structuredContent", "source")
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
