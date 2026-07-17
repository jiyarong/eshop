require "test_helper"

class ErpAI::ToolExecutorTest < ActiveSupport::TestCase
  class FakeMcpClient
    attr_reader :tool_name, :arguments

    def call_tool(tool_name, arguments)
      @tool_name = tool_name
      @arguments = arguments
      { "content" => [{ "type" => "text", "text" => "found" }] }
    end
  end

  test "dispatches namespaced MCP tool calls to matching client" do
    client = FakeMcpClient.new
    executor = ErpAI::ToolExecutor.new(mcp_clients: { "search" => client })

    result = executor.call(
      id: "call_1",
      name: "search__web_search",
      arguments: { "query" => "sku" }
    )

    assert_equal "web_search", client.tool_name
    assert_equal({ "query" => "sku" }, client.arguments)
    assert_equal "call_1", result.fetch(:tool_call_id)
    assert_equal "search__web_search", result.fetch(:name)
    assert_equal "found", result.fetch(:result).fetch("content").first.fetch("text")
  end

  test "returns structured error for unknown tool names" do
    executor = ErpAI::ToolExecutor.new(mcp_clients: {})

    result = executor.call(id: "call_2", name: "query_inventory_data", arguments: {})

    assert_equal "call_2", result.fetch(:tool_call_id)
    assert_equal "unknown_tool", result.fetch(:error).fetch(:code)
  end

  test "returns structured error for unknown MCP server names" do
    executor = ErpAI::ToolExecutor.new(mcp_clients: {})

    result = executor.call(id: "call_3", name: "missing__web_search", arguments: {})

    assert_equal "unknown_mcp_server", result.fetch(:error).fetch(:code)
  end

  test "returns structured error for MCP tools outside configured allowlist" do
    client = FakeMcpClient.new
    executor = ErpAI::ToolExecutor.new(
      mcp_clients: { "search" => client },
      mcp_tool_filters: { "search" => ["web_search"] }
    )

    result = executor.call(id: "call_4", name: "search__fetch_page", arguments: {})

    assert_nil client.tool_name
    assert_equal "mcp_tool_not_allowed", result.fetch(:error).fetch(:code)
  end
end
